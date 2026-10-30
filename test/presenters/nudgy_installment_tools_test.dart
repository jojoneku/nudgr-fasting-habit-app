import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 4 parity: mark an installment month paid and edit a plan
/// from chat, through the presenters the Installments list and the ledger
/// use. Each row shows exactly what the approve saves.

FinancialAccount _acc(String id, String name, AccountCategory c,
        {int? statementDay, int? dueDay}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: c,
      balance: 0,
      creditLimit: c == AccountCategory.bank ? null : 50000,
      statementDay: statementDay,
      paymentDueDay: dueDay,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

FinanceCategory _cat(String id, String name) => FinanceCategory(
      id: id,
      name: name,
      type: CategoryType.expense,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

final _now = DateTime.now();
String _month(int offset) =>
    toMonthKey(DateTime(_now.year, _now.month + offset));

/// A plan on the BNPL account (no statements), 6 months of ₱1000, started
/// two months ago — so three months are due and none is recorded.
Installment _plan({
  String id = 'p1',
  String accountId = 'atome',
  String? start,
  String? categoryId,
}) =>
    Installment(
      id: id,
      name: 'Phone',
      accountId: accountId,
      totalAmount: 6000,
      monthlyAmount: 1000,
      totalMonths: 6,
      startMonth: start ?? _month(-2),
      purchaseDate: DateTime(_now.year, _now.month - 3, 10),
      categoryId: categoryId,
    );

void main() {
  late MockStorageService storage;
  late LedgerPresenter ledger;
  late InstallmentPresenter installments;
  late FinanceActionsExecutor ex;
  late List<TransactionRecord> txns;
  late List<Installment> plans;

  Future<void> build(List<Installment> seed,
      {List<TransactionRecord> records = const []}) async {
    storage = MockStorageService();
    final stats = MockStatsPresenter();
    txns = [...records];
    plans = [...seed];
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          _acc('bpi', 'BPI', AccountCategory.bank),
          _acc('atome', 'Atome', AccountCategory.bnpl),
          _acc('bdo', 'BDO Card', AccountCategory.creditCard,
              statementDay: 5, dueDay: 25),
        ]);
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.loadFinanceCategories()).thenAnswer(
        (_) async => [_cat('gadgets', 'Gadgets'), _cat('shop', 'Shopping')]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => txns);
    when(storage.saveTransactions(any)).thenAnswer((inv) async {
      txns = List<TransactionRecord>.from(inv.positionalArguments.first);
    });
    when(storage.loadInstallments()).thenAnswer((_) async => plans);
    when(storage.saveInstallments(any)).thenAnswer((inv) async {
      plans = List<Installment>.from(inv.positionalArguments.first);
    });
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.awardStat(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    ledger = LedgerPresenter(storage, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
    while (ledger.isLoading || installments.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn(_month(0));
    when(bills.allBills).thenReturn([]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([]);
    ex = FinanceActionsExecutor(
        bills: bills, ledger: ledger, installments: installments);
  }

  Map<String, String> rows() =>
      {for (final d in ex.pending!.details) d.label: d.value};

  AiToolCall call(String name, Map<String, Object?> input) =>
      AiToolCall(id: 'c1', name: name, input: {'id': 'p1', ...input});

  /// Opens the row for [c]; the answer comes once the row is answered.
  /// Await [settle] before reading the row.
  Future<AiToolResult> open(AiToolCall c) => ex.propose(c);
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('both tools are updates with no recurrence scope field', () {
    for (final name in ['markInstallmentMonthPaid', 'editInstallment']) {
      final tool = financeToolNamed(name)!;
      expect(tool.kind, AiToolKind.update, reason: name);
      expect(
          (tool.inputSchema['properties'] as Map).containsKey('applyToFuture'),
          isFalse,
          reason: name);
    }
  });

  group('markInstallmentMonthPaid', () {
    test('the row shows the month, the count and the amount; that is saved',
        () async {
      await build([_plan()]);
      final answer = open(call('markInstallmentMonthPaid', {}));
      await settle();

      expect(ex.pending!.tier, ProposalTier.change);
      expect(rows()['Installment'], 'Phone');
      expect(rows()['Month'], _month(0));
      expect(rows()['Paid'], '0 of 6 → 1 of 6');
      expect(rows()['Amount'], '₱1000');
      expect(rows()['Charged to'], 'Atome (adds to its balance)');

      await ex.confirm();
      final r = await answer;
      expect(r.ok, isTrue);
      expect(r.summary, contains('payment 1 of 6'));
      final charge =
          ledger.allTransactions.singleWhere((t) => t.installmentId == 'p1');
      expect(charge.amount, 1000);
      expect(charge.month, _month(0));
      expect(charge.accountId, 'atome');
      expect(installments.paidCount('p1'), 1);
    });

    test('an amount and a month changed on the row are what is saved',
        () async {
      await build([_plan()]);
      final answer =
          open(call('markInstallmentMonthPaid', {'month': _month(-1)}));
      await settle();
      expect(ex.editAction('c1', {'amount': 950}), isNull);
      expect(rows()['Amount'], '₱950');
      expect(rows()['Month'], _month(-1));

      await ex.confirm();
      await answer;
      final charge =
          ledger.allTransactions.singleWhere((t) => t.installmentId == 'p1');
      expect(charge.amount, 950);
      expect(charge.month, _month(-1));
    });

    test('a bad id is refused before any row', () async {
      await build([_plan()]);
      final r = await ex.propose(const AiToolCall(
          id: 'x', name: 'markInstallmentMonthPaid', input: {'id': 'nope'}));
      expect(r.ok, isFalse);
      expect(r.summary, contains('"nope"'));
      expect(r.summary, contains('find (entity installment)'));
      expect(ex.batch, isNull);
    });

    test('a plan on a card with statements is refused: pay the statement',
        () async {
      await build([_plan(accountId: 'bdo')]);
      final r = await ex.propose(call('markInstallmentMonthPaid', {}));
      expect(r.ok, isFalse);
      expect(r.summary, contains('payCredit'));
      expect(ex.batch, isNull);
    });

    test('a month already paid, or not yet started, is refused', () async {
      final plan = _plan(start: _month(0));
      await build([
        plan
      ], records: [
        plan.chargeRecord(
          recordId: 'c',
          number: 1,
          date: _now,
          month: _month(0),
          categoryId: 'gadgets',
        ),
      ]);
      final paid = await ex.propose(call('markInstallmentMonthPaid', {}));
      expect(paid.summary, contains('already recorded'));

      final early = await ex
          .propose(call('markInstallmentMonthPaid', {'month': _month(-1)}));
      expect(early.summary, contains('no payment due'));
      expect(ex.batch, isNull);
      expect(ledger.allTransactions, hasLength(1));
    });
  });

  group('editInstallment', () {
    test('a plan with no ledger entry: a rename is T2 and only the name moves',
        () async {
      await build([_plan()]);
      final answer = open(call('editInstallment', {'name': 'iPhone'}));
      await settle();

      expect(ex.pending!.tier, ProposalTier.change);
      expect(rows(), {'Name': 'Phone → iPhone'});

      await ex.confirm();
      expect((await answer).ok, isTrue);
      final saved = installments.findById('p1')!;
      expect(saved.name, 'iPhone');
      expect(saved.monthlyAmount, 1000);
      expect(saved.startMonth, _plan().startMonth);
    });

    test('fewer months is T3: the row shows the new monthly payment saved',
        () async {
      await build([_plan()]);
      final answer = open(call('editInstallment', {'months': 3}));
      await settle();

      expect(ex.pending!.tier, ProposalTier.destructive);
      final shown = rows();
      expect(shown['Duration'], '6 → 3 months');
      expect(shown['Monthly payment'], '₱1000 → ₱2000');
      expect(shown['Also changes'], 'every later month of the plan');

      await ex.confirm();
      await answer;
      final saved = installments.findById('p1')!;
      expect(saved.totalMonths, 3);
      expect(saved.monthlyAmount, 2000);
    });

    test('a plan bought in the ledger: the purchase entry changes with it',
        () async {
      final plan = _plan(categoryId: 'gadgets');
      final purchase = TransactionRecord(
        id: 't1',
        date: plan.purchaseDate!,
        accountId: 'atome',
        categoryId: 'gadgets',
        amount: 6000,
        type: TransactionType.outflow,
        description: 'Phone',
        month: toMonthKey(plan.purchaseDate!),
        installmentId: 'p1',
        isInstallment: true,
      );
      await build([plan], records: [purchase]);
      final answer = open(
          call('editInstallment', {'name': 'iPhone', 'category': 'Shopping'}));
      await settle();

      expect(ex.pending!.tier, ProposalTier.destructive);
      final shown = rows();
      expect(shown['Name'], 'Phone → iPhone');
      expect(shown['Category'], 'Gadgets → Shopping');
      expect(shown['Also changes'], contains('purchase entry in the ledger'));

      await ex.confirm();
      expect((await answer).summary, contains('purchase entry'));
      final saved = installments.findById('p1')!;
      expect(saved.name, 'iPhone');
      expect(saved.categoryId, 'shop');
      final record = ledger.allTransactions.singleWhere((t) => t.id == 't1');
      expect(record.description, 'iPhone');
      expect(record.categoryId, 'shop');
      expect(record.isInstallment, isTrue);
    });

    test('a bad id is refused before any row', () async {
      await build([_plan()]);
      final r = await ex.propose(const AiToolCall(
          id: 'x',
          name: 'editInstallment',
          input: {'id': 'nope', 'months': 3}));
      expect(r.ok, isFalse);
      expect(r.summary, contains('"nope"'));
      expect(ex.batch, isNull);
    });

    test('no change, a non-credit account and too few months are refused',
        () async {
      final plan = _plan();
      await build([
        plan
      ], records: [
        for (var n = 1; n <= 3; n++)
          plan.chargeRecord(
            recordId: 'c$n',
            number: n,
            date: _now,
            month: _month(n - 3),
            categoryId: 'gadgets',
          ),
      ]);
      expect(
          (await ex.propose(call('editInstallment', {'name': 'Phone'})))
              .summary,
          contains('changes nothing'));
      expect(
          (await ex.propose(call('editInstallment', {'account': 'BPI'})))
              .summary,
          contains('not a credit account'));
      expect((await ex.propose(call('editInstallment', {'months': 2}))).summary,
          contains('3 payments'));
      expect(ex.batch, isNull);
      expect(installments.findById('p1')!.totalMonths, 6);
    });
  });
}
