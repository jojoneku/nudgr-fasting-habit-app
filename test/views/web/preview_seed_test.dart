import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/dev/preview_seed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The preview seed is the dataset every Plan 063 parity walk runs against,
/// so its shape is pinned here: the counts the design canvas was drawn with,
/// and referential integrity across the records (a bill pointing at an
/// account that does not exist renders as a blank, not an error).
void main() {
  late LocalStorageService storage;
  final month = toMonthKey(DateTime.now());

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    await storage.setUserId(PreviewSeed.userId);
    await PreviewSeed.seedInto(storage);
  });

  test(
      'seeds 23 accounts: 7 liquid (one overdrawn), 8 goals, 7 credit, 1 investment',
      () async {
    final accounts = await storage.loadAccounts();
    expect(accounts, hasLength(23));
    expect(accounts.where((a) => a.isLiquid), hasLength(7));
    expect(accounts.where((a) => a.category == AccountCategory.goal),
        hasLength(8));
    expect(accounts.where((a) => a.isLiability), hasLength(7));
    expect(accounts.where((a) => a.category == AccountCategory.investment),
        hasLength(1));
    expect(
        accounts.where((a) => a.isLiquid && a.balance < 0).map((a) => a.name),
        ['Maribank']);
    for (final goal
        in accounts.where((a) => a.category == AccountCategory.goal)) {
      expect(goal.hasGoalTarget, isTrue, reason: goal.name);
    }
    for (final card in accounts.where((a) => a.isLiability)) {
      expect(card.creditLimit, isNotNull, reason: card.name);
    }
  });

  test('seeds 11 bills for this month, 4 of them unpaid', () async {
    final bills = await storage.loadBills();
    final thisMonth = bills.where((b) => b.month == month).toList();
    expect(thisMonth, hasLength(11));
    final unpaid = thisMonth.where((b) => !b.isPaid).toList();
    expect(unpaid, hasLength(4));
    expect(unpaid.fold(0.0, (s, b) => s + b.amount), closeTo(7885, 0.005));
    expect(
      thisMonth.where((b) => b.isPaid).fold(0.0, (s, b) => s + b.amount),
      closeTo(12429.27, 0.005),
    );
  });

  test('seeds 2 receivables, 7 set-asides, 8 installments, 6 summaries',
      () async {
    expect(await storage.loadReceivables(), hasLength(2));
    final setAsides = await storage.loadBudgetedExpenses();
    expect(setAsides, hasLength(7));
    expect(setAsides.every((e) => !e.isPaid), isTrue);
    final plans = await storage.loadInstallments();
    expect(plans, hasLength(8));
    expect(plans.where((p) => p.isDueIn(month)), hasLength(6));
    final summaries = await storage.loadMonthlySummaries();
    expect(summaries, hasLength(6));
    expect(summaries.last.month, previousMonth(month));
    expect(summaries.map((s) => s.month).toSet(), hasLength(6));
  });

  test('every cross-record reference resolves', () async {
    final accountIds = {for (final a in await storage.loadAccounts()) a.id};
    final categoryIds = {
      for (final c in await storage.loadFinanceCategories()) c.id
    };
    final txns = await storage.loadTransactions();
    final txnIds = {for (final t in txns) t.id};
    final bills = await storage.loadBills();
    final billIds = {for (final b in bills) b.id};
    final plans = await storage.loadInstallments();
    final planIds = {for (final p in plans) p.id};

    for (final t in txns) {
      expect(accountIds, contains(t.accountId), reason: t.id);
      expect(categoryIds, contains(t.categoryId), reason: t.id);
      if (t.transferToAccountId != null) {
        expect(accountIds, contains(t.transferToAccountId), reason: t.id);
      }
      if (t.billId != null) expect(billIds, contains(t.billId), reason: t.id);
      if (t.installmentId != null) {
        expect(planIds, contains(t.installmentId), reason: t.id);
      }
    }
    for (final b in bills) {
      expect(categoryIds, contains(b.categoryId), reason: b.id);
      if (b.accountId != null) {
        expect(accountIds, contains(b.accountId), reason: b.id);
      }
      if (b.transactionId != null) {
        expect(txnIds, contains(b.transactionId), reason: b.id);
      }
    }
    for (final r in await storage.loadReceivables()) {
      expect(categoryIds, contains(r.categoryId), reason: r.id);
      if (r.accountId != null) {
        expect(accountIds, contains(r.accountId), reason: r.id);
      }
      if (r.transactionId != null) {
        expect(txnIds, contains(r.transactionId), reason: r.id);
      }
    }
    for (final e in await storage.loadBudgetedExpenses()) {
      expect(categoryIds, contains(e.categoryId), reason: e.id);
      expect(accountIds, contains(e.accountId), reason: e.id);
      expect(accountIds, contains(e.destinationAccountId), reason: e.id);
    }
    for (final p in plans) {
      expect(accountIds, contains(p.accountId), reason: p.id);
      if (p.categoryId != null) {
        expect(categoryIds, contains(p.categoryId), reason: p.id);
      }
    }
    // Savings budget rows key on the goal account; expense rows on a category.
    for (final b in await storage.loadBudgets()) {
      expect(
        accountIds.contains(b.categoryId) || categoryIds.contains(b.categoryId),
        isTrue,
        reason: b.id,
      );
    }
  });

  test('transfer legs come in pairs that point at each other', () async {
    final txns = await storage.loadTransactions();
    final legs = txns.where((t) => t.transferGroupId != null).toList();
    expect(legs, isNotEmpty);
    final byGroup = <String, List<dynamic>>{};
    for (final t in legs) {
      (byGroup[t.transferGroupId!] ??= []).add(t);
    }
    for (final pair in byGroup.values) {
      expect(pair, hasLength(2));
      expect(pair[0].accountId, pair[1].transferToAccountId);
      expect(pair[1].accountId, pair[0].transferToAccountId);
      expect(pair[0].amount, pair[1].amount);
    }
  });

  test('seeding again replaces, never duplicates', () async {
    await PreviewSeed.seedInto(storage);
    expect(await storage.loadAccounts(), hasLength(23));
    expect(await storage.loadBills(), hasLength(11));
    expect(await storage.loadInstallments(), hasLength(8));
  });
}
