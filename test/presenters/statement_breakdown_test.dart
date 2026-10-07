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
import 'package:intermittent_fasting/utils/credit_cycle.dart';
import 'package:intermittent_fasting/utils/credit_statement_breakdown.dart';
import 'package:intermittent_fasting/utils/statement_card_view.dart';
import '../mocks.mocks.dart';

/// A credit statement's item list: the card's records inside the cycle,
/// grouped like an issuer's bill screen, with totals that add up to the bill
/// amount and to statement progress.
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

  TransactionRecord rec(
    String id,
    DateTime date,
    double amount, {
    String accountId = 'spay',
    TransactionType type = TransactionType.outflow,
    String description = 'Purchase',
    String? transferGroupId,
    String? transferToAccountId,
    bool isInstallment = false,
    String? installmentId,
  }) =>
      TransactionRecord(
        id: id,
        date: date,
        accountId: accountId,
        categoryId: 'cat-shop',
        amount: amount,
        type: type,
        description: description,
        month: '${date.year}-${date.month.toString().padLeft(2, '0')}',
        transferGroupId: transferGroupId,
        transferToAccountId: transferToAccountId,
        isInstallment: isInstallment,
        installmentId: installmentId,
      );

  StatementBreakdown breakdown() => bills.statementBreakdown(statement())!;

  /// The lines add up to the bill, and what is left matches statement
  /// progress and [creditStatementRemaining] exactly.
  void expectReconciles(StatementBreakdown b) {
    final bill = statement();
    expect(b.billAmount, closeTo(bill.amount, 0.005));
    expect(b.linesTotal, closeTo(b.billAmount, 0.005));
    expect(b.unreconciled, 0);
    expect(b.billAmount - b.repaid, closeTo(b.unpaid, 0.005));
    expect(b.unpaid, closeTo(creditStatementRemaining(bill), 0.005));
    expect(b.unpaid, closeTo(remaining(), 0.005));
    expect(b.repaid, closeTo(bills.statementProgress(bill)!.paid, 0.005));
  }

  group('statementBreakdown', () {
    test('ShopeePay cycle: 3 purchases + 6 installment months = ₱2,424.40',
        () async {
      txnState = [
        rec('a', DateTime(2026, 9, 5), 20.09, description: 'Phone case'),
        rec('b', DateTime(2026, 9, 18), 449.35, description: 'Groceries'),
        // On the close day itself: still this statement.
        rec('c', DateTime(2026, 10, 4), 376.25, description: 'Shoes'),
        // The installment purchase record moves no money — never a line.
        rec('buy', DateTime(2026, 9, 20), 898.86,
            description: 'Item 0', isInstallment: true, installmentId: 'p0'),
        // Another account's spending is not on this card.
        rec('bank-spend', DateTime(2026, 9, 20), 5000, accountId: 'bank'),
      ];
      build();
      await loadAll();

      final b = breakdown();
      expect(b.cycle.start, DateTime(2026, 9, 5));
      expect(b.cycle.close, DateTime(2026, 10, 4));
      expect(b.periodLabel, '05 Sep – 04 Oct');

      expect(b.purchases.map((l) => l.txn.id), ['a', 'b', 'c']);
      expect(b.purchasesTotal, closeTo(845.69, 0.005));
      expect(b.installments, hasLength(6));
      expect(b.installmentsTotal, closeTo(1578.71, 0.005));
      final first =
          b.installments.firstWhere((l) => l.txn.installmentId == 'p0');
      expect(first.title, 'Item 0');
      expect(first.installmentLabel, '1/3');
      expect(first.amount, closeTo(299.62, 0.005));
      expect(b.refunds, isEmpty);
      expect(b.repayments, isEmpty);
      expect(b.carriedOver, closeTo(0, 0.005));
      expect(b.hasCarriedOver, isFalse);
      expect(b.itemCount, 9);
      expect(b.itemCountLabel, '9 items');

      expect(b.billAmount, closeTo(2424.40, 0.005));
      expect(b.repaid, 0);
      expect(b.unpaid, closeTo(2424.40, 0.005));
      expectReconciles(b);
      expect(bills.statementItemsLabel(statement()), 'View items · 9');

      // Nothing from another account, nor the purchase record, is listed.
      final all = [
        ...b.purchases,
        ...b.installments,
        ...b.refunds,
        ...b.repayments,
      ];
      expect(all.every((l) => l.txn.accountId == 'spay'), isTrue);
      expect(all.any((l) => l.txn.isInstallment), isFalse);
    });

    test('a refund, a payment during the cycle and a part payment reconcile',
        () async {
      // Owed ₱1,000 at the Sep 4 close; ₱600 of it paid on Sep 10. Then ₱300
      // spent and ₱50 refunded. Balance today, before the close's installment
      // months are billed: 1000 − 600 + 300 − 50 = ₱650.
      accountsState = [spay(balance: 650), billease, bank];
      txnState = [
        rec('pay-out', DateTime(2026, 9, 10), 600,
            accountId: 'bank',
            description: 'Paid SPayLater',
            transferGroupId: 'g1',
            transferToAccountId: 'spay'),
        rec('pay-in', DateTime(2026, 9, 10), 600,
            type: TransactionType.inflow,
            description: 'Paid SPayLater',
            transferGroupId: 'g1',
            transferToAccountId: 'bank'),
        rec('buy', DateTime(2026, 9, 15), 300, description: 'Headphones'),
        rec('refund', DateTime(2026, 9, 20), 50,
            type: TransactionType.inflow, description: 'Voucher refund'),
      ];
      build();
      await loadAll();

      var b = breakdown();
      expect(b.previousBalance, closeTo(1000, 0.005));
      expect(b.paidDuringCycle, closeTo(600, 0.005));
      expect(b.carriedOver, closeTo(400, 0.005));
      expect(b.purchasesTotal, closeTo(300, 0.005));
      expect(b.refunds.single.txn.id, 'refund');
      expect(b.refundsTotal, closeTo(50, 0.005));
      // 400 + 300 + 1,578.71 − 50.
      expect(b.billAmount, closeTo(2228.71, 0.005));
      expect(b.itemCount, 8);
      expectReconciles(b);

      // Part payment after the close: it is "Repaid", the rest stays unpaid.
      await ledger.addTransfer(
        fromAccountId: 'bank',
        toAccountId: 'spay',
        amount: 850,
        description: 'Paid SPayLater',
        date: DateTime(2026, 10, 6),
      );
      b = breakdown();
      expect(b.repayments, hasLength(1));
      expect(b.repayments.single.txn.accountId, 'spay');
      expect(b.repaymentsTotal, closeTo(850, 0.005));
      expect(b.repaid, closeTo(850, 0.005));
      expect(b.unpaid, closeTo(1378.71, 0.005));
      expectReconciles(b);

      // Editing a line updates the breakdown — and the statement with it.
      final buy = ledger.allTransactions.firstWhere((t) => t.id == 'buy');
      await ledger.updateTransaction(buy.copyWith(amount: 400));
      b = breakdown();
      expect(b.purchasesTotal, closeTo(400, 0.005));
      expect(statement().amount, closeTo(2328.71, 0.005));
      expect(b.unpaid, closeTo(1478.71, 0.005));
      expectReconciles(b);
    });

    test('the close day is in; the day after rides the next statement',
        () async {
      // ₱0.01 left from the previous cycle, ₱845.69 in this one, and ₱100
      // spent the day after the close.
      accountsState = [spay(balance: 945.70), billease, bank];
      txnState = [
        rec('before', DateTime(2026, 9, 4), 0.01),
        rec('first-day', DateTime(2026, 9, 5), 20.09),
        rec('mid', DateTime(2026, 9, 18), 449.35),
        rec('close-day', DateTime(2026, 10, 4, 23, 59), 376.25),
        rec('after', DateTime(2026, 10, 5), 100),
      ];
      build();
      await loadAll();

      final b = breakdown();
      expect(
          b.purchases.map((l) => l.txn.id), ['first-day', 'mid', 'close-day']);
      expect(b.carriedOver, closeTo(0.01, 0.005));
      expect(b.billAmount, closeTo(2424.41, 0.005));
      // A charge after the close is not a payment either.
      expect(b.repayments, isEmpty);
      expectReconciles(b);
    });

    test('null for a bill that is not a credit statement', () async {
      await loadAll();
      final rent = Bill(
        id: 'rent',
        name: 'Rent',
        billType: BillType.other,
        amount: 12000,
        dueDay: 5,
        month: '2026-10',
        categoryId: 'cat-shop',
      );
      expect(bills.statementBreakdown(rent), isNull);
      expect(bills.statementItemsLabel(rent), isNull);
    });
  });
  group('statement card and installment rows', () {
    List<TransactionRecord> shopeeCycle() => [
          rec('a', DateTime(2026, 9, 5), 20.09, description: 'Phone case'),
          rec('b', DateTime(2026, 9, 18), 449.35, description: 'Groceries'),
          rec('c', DateTime(2026, 10, 4), 376.25, description: 'Shoes'),
        ];

    test('the card leads with the account and says what is on it', () async {
      txnState = shopeeCycle();
      build();
      await loadAll();

      final card = bills.statementCard(statement())!;
      expect(card.account.id, 'spay');
      expect(card.kindLabel, 'BNPL');
      expect(card.periodLabel, 'Statement · 05 Sep – 04 Oct');
      expect(card.dueLabel, 'Due Oct 15 · in 8 days');
      expect(card.dueTone, StatementDueTone.normal);
      expect(card.headlineAmount, closeTo(2424.40, 0.005));
      expect(card.headlineCaption, 'To pay');
      expect(card.compositionLabel, '3 purchases · 6 installments');
      expect(card.itemsLabel, 'View 9 items');
      expect(card.progress, isNull);
    });

    test('a due date within three days reads as soon', () async {
      txnState = shopeeCycle();
      build(now: DateTime(2026, 10, 13));
      await loadAll();

      final card = bills.statementCard(statement())!;
      expect(card.dueLabel, 'Due Oct 15 · in 2 days');
      expect(card.dueTone, StatementDueTone.soon);
    });

    test('a part payment shows what is left and the progress', () async {
      txnState = shopeeCycle();
      build();
      await loadAll();

      await bills.markBillPaid(statement().id,
          paidAmount: 850, accountId: 'bank');

      final card = bills.statementCard(statement())!;
      expect(card.headlineAmount, closeTo(1574.40, 0.005));
      expect(card.headlineCaption, 'Left of ₱2,424.40');
      expect(card.progress, closeTo(850 / 2424.40, 0.0001));
      expect(card.progressLabel, startsWith('Paid ₱850.00 of ₱2,424.40'));
    });

    test('a billed month is not paid until its statement is', () async {
      txnState = shopeeCycle();
      build();
      await loadAll();
      final plan = installments.installments.firstWhere((i) => i.id == 'p0');

      final open = bills.installmentStatementStatus(plan)!;
      expect(open.paid, isFalse);
      expect(open.label, '1/3 · on statement, due Oct 15');
      expect(open.statement?.id, statement().id);
      expect(open.linkLabel, 'View SPayLater statement');
      // Billed onto the open statement, not paid: the bar has not moved.
      expect(open.progress, 0);
      expect(open.note, "Linked to SPayLater statement · can't be paid alone");

      await bills.markBillPaid(statement().id,
          paidAmount: 2424.40, accountId: 'bank');

      final settled = bills.installmentStatementStatus(plan)!;
      expect(settled.paid, isTrue);
      expect(settled.label, '1/3 · paid with statement');
      expect(settled.progress, closeTo(1 / 3, 0.0001));
    });

    test('a plan on a card without statements keeps its own row state',
        () async {
      planState = sixPlans(accountId: 'billease');
      build();
      await loadAll();

      final plan = installments.installments.first;
      expect(bills.installmentStatementStatus(plan), isNull);
    });
  });
}
