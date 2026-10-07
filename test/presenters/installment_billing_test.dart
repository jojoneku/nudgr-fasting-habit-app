import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../mocks.mocks.dart';

/// Installments are billed onto the card when its statement closes: one charge
/// per plan per cycle, on the card, in the plan's category. The statement is
/// then just the card's balance at close, and every way of paying it — Bills
/// "Pay", quick pay, a transfer typed into the ledger — is a plain transfer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;
  late LedgerPresenter ledger;
  late InstallmentPresenter installments;
  late BillsReceivablesPresenter bills;

  late List<FinancialAccount> accountsState;
  late List<TransactionRecord> txnState;
  late List<Installment> planState;
  late List<Bill> billState;

  final shopping = FinanceCategory(
    id: 'cat-shop',
    name: 'Shopping',
    colorHex: '#3366FF',
    icon: 'bag',
    type: CategoryType.expense,
  );

  // The real account behind the ShopeePay bug report: statement on the 4th,
  // due the 15th, ₱845.69 of ordinary (revolving) spend on it.
  FinancialAccount spay({double balance = 845.69}) => FinancialAccount(
        id: 'spay',
        name: 'SPayLater',
        category: AccountCategory.bnpl,
        balance: balance,
        creditLimit: 20000,
        statementDay: 4,
        paymentDueDay: 15,
        colorHex: '#EE4D2D',
        icon: 'wallet',
      );

  // A BNPL with no billing cycle — no statements, paid row by row.
  final billease = FinancialAccount(
    id: 'billease',
    name: 'BillEase',
    category: AccountCategory.bnpl,
    balance: 0,
    colorHex: '#00AA88',
    icon: 'wallet',
  );

  final bank = FinancialAccount(
    id: 'bank',
    name: 'MariBank',
    category: AccountCategory.bank,
    balance: 50000,
    colorHex: '#123456',
    icon: 'bank',
  );

  const monthlies = [299.62, 82.92, 372.76, 46.46, 567.79, 209.16];

  List<Installment> sixPlans({String accountId = 'spay'}) => [
        for (var i = 0; i < monthlies.length; i++)
          Installment(
            id: 'p$i',
            name: 'Item $i',
            accountId: accountId,
            totalAmount: monthlies[i] * 3,
            monthlyAmount: monthlies[i],
            totalMonths: 3,
            startMonth: '2026-10',
            purchaseDate: DateTime(2026, 9, 20),
            categoryId: i.isEven ? 'cat-shop' : null,
          ),
      ];

  FinancialAccount acct(String id) =>
      ledger.accounts.firstWhere((a) => a.id == id);

  List<TransactionRecord> charges() => ledger.allTransactions
      .where((t) => t.installmentId != null && !t.isInstallment)
      .toList();

  Bill statement() => bills.allBills.firstWhere((b) =>
      b.isAutoStatement && b.accountId == 'spay' && b.month == '2026-10');

  double remaining() =>
      bills.statementProgress(statement())?.remaining ?? double.nan;

  void build({DateTime? now}) {
    ledger = LedgerPresenter(storage, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
    bills = BillsReceivablesPresenter(
      storage,
      ledger,
      stats,
      notifications: notifications,
      installments: installments,
      clock: () => now ?? DateTime(2026, 10, 7),
    );
  }

  Future<void> loadAll() async {
    await ledger.load();
    await installments.load();
    await bills.load();
    installments.setMonth('2026-10');
    await bills.setMonth('2026-10');
  }

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();

    accountsState = [spay(), billease, bank];
    txnState = [];
    planState = sixPlans();
    billState = [];

    when(storage.loadAccounts()).thenAnswer((_) async => accountsState);
    when(storage.saveAccounts(any)).thenAnswer((inv) async {
      accountsState =
          List<FinancialAccount>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [shopping]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => txnState);
    when(storage.saveTransactions(any)).thenAnswer((inv) async {
      txnState =
          List<TransactionRecord>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadInstallments()).thenAnswer((_) async => planState);
    when(storage.saveInstallments(any)).thenAnswer((inv) async {
      planState = List<Installment>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadBills()).thenAnswer((_) async => billState);
    when(storage.saveBills(any)).thenAnswer((inv) async {
      billState = List<Bill>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadDismissedStatementKeys())
        .thenAnswer((_) async => <String>{});
    when(storage.saveDismissedStatementKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.awardStat(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    build();
  });

  group('statement close bills each installment month onto the card', () {
    test('worked example: six 3-month plans on a card closing the 4th',
        () async {
      await loadAll();

      // One charge per plan, on the card, dated the close.
      final posted = charges();
      expect(posted, hasLength(6));
      for (final c in posted) {
        expect(c.accountId, 'spay');
        expect(c.type, TransactionType.outflow);
        expect(c.date, DateTime(2026, 10, 4));
        expect(c.month, '2026-10');
        expect(c.description, endsWith('— Installment 1/3'));
      }
      // The plan's own category, else the installment fallback.
      expect(posted.firstWhere((c) => c.installmentId == 'p0').categoryId,
          'cat-shop');
      expect(posted.firstWhere((c) => c.installmentId == 'p1').categoryId,
          kInstallmentCategoryId);
      expect(
          ledger.categories.any((c) => c.id == kInstallmentCategoryId), isTrue);

      final card = acct('spay');
      expect(card.balance, closeTo(2424.40, 0.005));
      expect(card.unbilledInstallments, closeTo(3157.42, 0.005));
      // Total owed is unchanged — a month only moves from unbilled to billed.
      expect(card.totalDebt, closeTo(5581.82, 0.005));

      final s = statement();
      expect(s.amount, closeTo(2424.40, 0.005));
      expect(s.dueDay, 15);
      expect(s.isPaid, isFalse);
    });

    test('regenerating posts nothing twice (idempotent by count)', () async {
      await loadAll();
      await bills.setMonth('2026-10');
      await bills.load();

      // A fresh app start over the saved data bills nothing again either.
      build();
      await loadAll();

      expect(charges(), hasLength(6));
      expect(acct('spay').balance, closeTo(2424.40, 0.005));
      expect(statement().amount, closeTo(2424.40, 0.005));
      expect(bills.allBills.where((b) => b.isAutoStatement).toList(),
          hasLength(1));
    });

    test('a payment booked under the old model is not billed again', () async {
      // The old Bills "Pay" booked p0's month as an outflow from the bank.
      txnState = [
        TransactionRecord(
          id: 'old-pay',
          date: DateTime(2026, 9, 30),
          accountId: 'bank',
          categoryId: 'cat-shop',
          amount: monthlies[0],
          type: TransactionType.outflow,
          description: 'Item 0 — Payment 1/3',
          month: '2026-09',
          installmentId: 'p0',
        ),
      ];
      build();
      await loadAll();

      expect(charges().where((c) => c.accountId == 'spay'), hasLength(5));
      expect(charges().where((c) => c.installmentId == 'p0'), hasLength(1));
      expect(installments.isPaidForMonth('p0'), isTrue);
    });

    test('a cycle that has not closed yet bills nothing', () async {
      build(now: DateTime(2026, 10, 3));
      await loadAll();

      expect(charges(), isEmpty);
      expect(acct('spay').balance, closeTo(845.69, 0.005));
      expect(acct('spay').unbilledInstallments, closeTo(4736.13, 0.005));
    });

    test('nothing is posted for a statement already paid before the change',
        () async {
      // The October statement was generated and paid in full under the old
      // model (a quick pay), before any charge existed.
      billState = [
        Bill(
          id: 'old-stmt',
          name: 'SPayLater statement',
          billType: BillType.creditCard,
          amount: 2424.40,
          dueDay: 15,
          month: '2026-10',
          categoryId: 'cat-shop',
          accountId: 'spay',
          paymentNote: Bill.autoStatementNote,
          isPaid: true,
          paidAmount: 2424.40,
          paidDate: DateTime(2026, 10, 5),
        ),
      ];
      build();
      await loadAll();

      expect(charges(), isEmpty);
      expect(acct('spay').balance, closeTo(845.69, 0.005));
      expect(acct('spay').unbilledInstallments, closeTo(4736.13, 0.005));
      expect(statement().isPaid, isTrue);
      expect(statement().amount, closeTo(2424.40, 0.005));
    });

    test('past-due cycles are never backfilled', () async {
      // September's statement (due Sep 15) is long past due on Oct 7; plans
      // that started in September are billed only by the open statement.
      planState = [
        for (final p in sixPlans()) p.copyWith(startMonth: '2026-09'),
      ];
      build();
      await loadAll();

      // Count-based: by the October statement each plan owes 2 months.
      expect(charges(), hasLength(12));
      expect(charges().every((c) => c.date == DateTime(2026, 10, 4)), isTrue);
      expect(bills.allBills.where((b) => b.isAutoStatement).map((b) => b.month),
          ['2026-10']);
    });
  });

  group('paying the statement is a plain transfer', () {
    test('a part payment moves only what was paid, and the rest stays owed',
        () async {
      await loadAll();

      await bills.markBillPaid(statement().id,
          paidAmount: 850, accountId: 'bank', paidDate: DateTime(2026, 10, 7));

      expect(acct('bank').balance, closeTo(50000 - 850, 0.005));
      expect(acct('spay').balance, closeTo(1574.40, 0.005));
      expect(remaining(), closeTo(1574.40, 0.005));
      expect(statement().isPaid, isFalse);

      // Regenerating keeps the statement whole: the installment months are on
      // the card, not excluded as "paid this month".
      await bills.setMonth('2026-10');
      expect(statement().amount, closeTo(2424.40, 0.005));
      expect(remaining(), closeTo(1574.40, 0.005));
      // Nothing in the payment was booked as spending.
      expect(
          ledger.allTransactions.where((t) =>
              t.accountId == 'bank' &&
              t.type == TransactionType.outflow &&
              t.transferGroupId == null),
          isEmpty);
    });

    test('H1: ₱3,000 + ₱2,000 statement, pay ₱2,500 → ₱2,500 left', () async {
      accountsState = [spay(balance: 3000), bank];
      planState = [
        Installment(
          id: 'tv',
          name: 'TV',
          accountId: 'spay',
          totalAmount: 6000,
          monthlyAmount: 2000,
          totalMonths: 3,
          startMonth: '2026-10',
        ),
      ];
      build();
      await loadAll();
      expect(statement().amount, closeTo(5000, 0.005));

      await bills.markBillPaid(statement().id,
          paidAmount: 2500, accountId: 'bank', paidDate: DateTime(2026, 10, 7));
      await bills.setMonth('2026-10');

      expect(statement().amount, closeTo(5000, 0.005));
      expect(remaining(), closeTo(2500, 0.005));
      expect(acct('spay').balance, closeTo(2500, 0.005));
      expect(acct('bank').balance, closeTo(47500, 0.005));
    });

    test('quick pay settles the statement without releasing anything extra',
        () async {
      await loadAll();

      await bills.quickPayCard(
          accountId: 'spay', fromAccountId: 'bank', amount: 2424.40);

      final card = acct('spay');
      expect(card.balance, closeTo(0, 0.005));
      expect(card.balance >= -0.005, isTrue, reason: 'never overpaid');
      // The hold still covers exactly the two unbilled months of each plan.
      expect(card.unbilledInstallments, closeTo(3157.42, 0.005));
      expect(card.totalDebt, closeTo(3157.42, 0.005));
      expect(statement().isPaid, isTrue);
      expect(charges(), hasLength(6));
    });

    test('a transfer typed into the ledger by hand settles the statement',
        () async {
      await loadAll();

      await ledger.addTransfer(
        fromAccountId: 'bank',
        toAccountId: 'spay',
        amount: 2424.40,
        description: 'Paid SPayLater',
        date: DateTime(2026, 10, 8),
      );

      expect(statement().isPaid, isTrue);
      expect(acct('spay').balance, closeTo(0, 0.005));
      expect(acct('spay').unbilledInstallments, closeTo(3157.42, 0.005));
    });

    test('undoing a statement payment leaves the billed charges alone',
        () async {
      await loadAll();
      await bills.markBillPaid(statement().id,
          paidAmount: 2424.40,
          accountId: 'bank',
          paidDate: DateTime(2026, 10, 7));
      expect(statement().isPaid, isTrue);

      await bills.markBillUnpaid(statement().id);

      expect(statement().isPaid, isFalse);
      expect(charges(), hasLength(6));
      expect(acct('spay').balance, closeTo(2424.40, 0.005));
      expect(acct('bank').balance, closeTo(50000, 0.005));
    });
  });

  group('rows on a card with statements', () {
    test('offer no Mark paid, and markPaid is a no-op', () async {
      await loadAll();
      final plan = installments.installments.first;

      expect(installments.billsOnStatement(plan), isTrue);
      expect(installments.canMarkPaid(plan), isFalse);
      expect(installments.canMarkUnpaid(plan), isFalse);
      expect(installments.isPaidForMonth(plan.id), isTrue);
      expect(installments.statusLabel(plan), 'billed · 1/3');

      await installments.markPaid(plan.id, fundingAccountId: 'bank');
      await installments.markUnpaid(plan.id);
      expect(charges(), hasLength(6));
      expect(acct('bank').balance, closeTo(50000, 0.005));
    });

    test('before the close the row reads as waiting for the statement',
        () async {
      build(now: DateTime(2026, 10, 3));
      await loadAll();
      final plan = installments.installments.first;
      expect(installments.statusLabel(plan), 'on statement · 1/3');
      expect(installments.canMarkPaid(plan), isFalse);
    });
  });

  group('a BNPL with no billing cycle keeps a manual path', () {
    setUp(() {
      planState = sixPlans(accountId: 'billease').take(1).toList();
    });

    test('Mark paid charges the card and pays it from the funding account',
        () async {
      build();
      await loadAll();
      final plan = installments.installments.single;
      expect(installments.billsOnStatement(plan), isFalse);
      expect(installments.canMarkPaid(plan), isTrue);
      // No statements, so nothing is billed automatically.
      expect(charges(), isEmpty);

      await installments.markPaid(plan.id,
          fundingAccountId: 'bank', date: DateTime(2026, 10, 7));

      final posted = charges().single;
      expect(posted.accountId, 'billease');
      expect(posted.type, TransactionType.outflow);
      expect(posted.categoryId, 'cat-shop');
      expect(acct('billease').balance, closeTo(0, 0.005));
      expect(acct('billease').unbilledInstallments,
          closeTo(monthlies[0] * 2, 0.005));
      expect(acct('bank').balance, closeTo(50000 - monthlies[0], 0.005));
      expect(installments.isPaidForMonth(plan.id), isTrue);
      expect(installments.canMarkUnpaid(plan), isTrue);

      await installments.markUnpaid(plan.id);

      expect(charges(), isEmpty);
      expect(ledger.allTransactions.where((t) => t.transferGroupId != null),
          isEmpty);
      expect(acct('bank').balance, closeTo(50000, 0.005));
      expect(acct('billease').balance, closeTo(0, 0.005));
      expect(acct('billease').unbilledInstallments,
          closeTo(monthlies[0] * 3, 0.005));
    });

    test('Mark paid without a funding account leaves the charge owed',
        () async {
      build();
      await loadAll();
      final plan = installments.installments.single;

      await installments.markPaid(plan.id, date: DateTime(2026, 10, 7));

      expect(acct('billease').balance, closeTo(monthlies[0], 0.005));
      expect(acct('billease').totalDebt, closeTo(monthlies[0] * 3, 0.005));
    });

    test('paid early is still paid in its own month (count, not month key)',
        () async {
      // October's month, paid on Sep 30 and filed under September.
      txnState = [
        TransactionRecord(
          id: 'early',
          date: DateTime(2026, 9, 30),
          accountId: 'billease',
          categoryId: 'cat-shop',
          amount: monthlies[0],
          type: TransactionType.outflow,
          description: 'Item 0 — Installment 1/3',
          month: '2026-09',
          installmentId: 'p0',
        ),
      ];
      build();
      await loadAll();
      final plan = installments.installments.single;

      expect(installments.isPaidForMonth(plan.id), isTrue);
      expect(installments.canMarkPaid(plan), isFalse);
      await installments.markPaid(plan.id);
      expect(charges(), hasLength(1), reason: 'not booked a second time');

      // A month the plan has not reached offers nothing to pay.
      installments.setMonth('2026-09');
      expect(installments.canMarkPaid(plan), isFalse);
    });
  });

  group('Coming Up', () {
    test('a cycle card installment appears only inside its statement',
        () async {
      planState = [
        ...sixPlans(),
        Installment(
          id: 'manual',
          name: 'Manual plan',
          accountId: 'billease',
          totalAmount: 300,
          monthlyAmount: 100,
          totalMonths: 3,
          startMonth: '2026-10',
        ),
      ];
      build();
      await loadAll();

      final items = bills.comingUpItems(installments);
      final statements = items.where((i) => i.kind == ComingUpKind.bill);
      expect(statements, hasLength(1));
      expect(statements.single.amount, closeTo(2424.40, 0.005));
      final rows = items.where((i) => i.kind == ComingUpKind.installment);
      expect(rows.map((i) => i.name), ['Manual plan']);
    });

    test('before the close, cycle installments are not listed either',
        () async {
      build(now: DateTime(2026, 10, 3));
      await loadAll();

      final items = bills.comingUpItems(installments);
      expect(items.where((i) => i.kind == ComingUpKind.installment), isEmpty);
    });
  });
}
