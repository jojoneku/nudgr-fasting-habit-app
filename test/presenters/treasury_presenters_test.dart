import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

FinancialAccount _account({
  required String id,
  String name = 'Account',
  AccountCategory category = AccountCategory.ewallet,
  double balance = 0,
  String? parentAccountId,
  bool isActive = true,
}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: category,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
      parentAccountId: parentAccountId,
      isActive: isActive,
    );

TransactionRecord _txn({
  required String id,
  required String accountId,
  required double amount,
  required TransactionType type,
  String? month,
  String? transferGroupId,
  String? transferToAccountId,
  String categoryId = '',
  bool reimbursable = false,
  String? reimbursementReceivableId,
  String? receivableId,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime(2026, 3, 15),
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      description: 'Test',
      month: month ?? '2026-03',
      transferGroupId: transferGroupId,
      transferToAccountId: transferToAccountId,
      reimbursable: reimbursable,
      reimbursementReceivableId: reimbursementReceivableId,
      receivableId: receivableId,
    );

Bill _bill({
  required String id,
  double amount = 100,
  bool isPaid = false,
  String month = '2026-03',
  String categoryId = '',
  bool isRecurring = false,
  BillType billType = BillType.utility,
  String? accountId,
}) =>
    Bill(
      id: id,
      name: 'Bill $id',
      billType: billType,
      amount: amount,
      dueDay: 10,
      month: month,
      categoryId: categoryId,
      isPaid: isPaid,
      isRecurring: isRecurring,
      accountId: accountId,
    );

Receivable _receivable({
  required String id,
  double amount = 200,
  bool isReceived = false,
  String month = '2026-03',
}) =>
    Receivable(
      id: id,
      name: 'Receivable $id',
      receivableType: ReceivableType.salary,
      amount: amount,
      expectedDate: DateTime(2026, 3, 20),
      month: month,
      categoryId: '',
      isReceived: isReceived,
    );

FinanceCategory _category({
  required String id,
  CategoryType type = CategoryType.expense,
  String name = 'Category',
}) =>
    FinanceCategory(
      id: id,
      name: name,
      type: type,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

// ─── TreasuryDashboardPresenter ───────────────────────────────────────────────

void main() {
  group('TreasuryDashboardPresenter', () {
    late MockStorageService mockStorage;
    late TreasuryDashboardPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      when(mockStorage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(mockStorage.loadAccounts()).thenAnswer((_) async => []);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.loadBills()).thenAnswer((_) async => []);
      when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
      when(mockStorage.loadBudgets()).thenAnswer((_) async => []);
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => []);
      when(mockStorage.saveMonthlySummaries(any)).thenAnswer((_) async {});
      when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
      presenter = TreasuryDashboardPresenter(mockStorage);
    });

    test('liquidAccounts returns only active liquid top-level accounts',
        () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'a1', category: AccountCategory.ewallet, balance: 500),
            _account(
                id: 'a2', category: AccountCategory.creditCard, balance: 200),
            _account(
                id: 'a3',
                category: AccountCategory.savings,
                balance: 100,
                parentAccountId: 'a1'),
          ]);
      await presenter.load();
      expect(presenter.liquidAccounts.map((a) => a.id), ['a1']);
    });

    test('liabilityAccounts returns creditCard/creditLine/bnpl', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'a1', category: AccountCategory.creditCard, balance: 300),
            _account(id: 'a2', category: AccountCategory.bnpl, balance: 150),
            _account(
                id: 'a3', category: AccountCategory.ewallet, balance: 1000),
          ]);
      await presenter.load();
      expect(presenter.liabilityAccounts.map((a) => a.id),
          containsAll(['a1', 'a2']));
      expect(presenter.liabilityAccounts.any((a) => a.id == 'a3'), isFalse);
    });

    test('totalLiquidCash sums liquid account balances', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'a1', category: AccountCategory.ewallet, balance: 1000),
            _account(id: 'a2', category: AccountCategory.bank, balance: 2500),
            _account(
                id: 'a3', category: AccountCategory.creditCard, balance: 500),
          ]);
      await presenter.load();
      expect(presenter.totalLiquidCash, 3500);
    });

    test('netWorth = assets - liabilities', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'a1', category: AccountCategory.bank, balance: 5000),
            _account(
                id: 'a2', category: AccountCategory.creditCard, balance: 1000),
          ]);
      await presenter.load();
      expect(presenter.netWorth, 4000);
    });

    test('pendingReceivables sums unReceived receivables for current month',
        () async {
      final month = toMonthKey(DateTime.now());
      when(mockStorage.loadReceivables()).thenAnswer((_) async => [
            _receivable(id: 'r1', amount: 500, isReceived: false, month: month),
            _receivable(id: 'r2', amount: 300, isReceived: true, month: month),
          ]);
      await presenter.load();
      expect(presenter.pendingReceivables, 500);
    });

    test('deleteAccount throws StateError when sub-accounts exist', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'parent'),
            _account(id: 'child', parentAccountId: 'parent'),
          ]);
      await presenter.load();
      expect(
          () => presenter.deleteAccount('parent'), throwsA(isA<StateError>()));
    });

    test('deleteAccount removes account and saves', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'a1'),
          ]);
      await presenter.load();
      await presenter.deleteAccount('a1');
      expect(presenter.liquidAccounts.any((a) => a.id == 'a1'), isFalse);
      verify(mockStorage.saveAccounts(argThat(isEmpty))).called(1);
    });

    test('addAccount persists to storage', () async {
      await presenter.load();
      final account =
          _account(id: 'new1', category: AccountCategory.bank, balance: 0);
      await presenter.addAccount(account);
      verify(mockStorage.saveAccounts(any)).called(1);
    });
  });

  // ─── LedgerPresenter ──────────────────────────────────────────────────────

  group('LedgerPresenter', () {
    late MockStorageService mockStorage;
    late MockStatsPresenter mockStats;
    late LedgerPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      when(mockStorage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      mockStats = MockStatsPresenter();

      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'gcash', category: AccountCategory.ewallet, balance: 1000),
            _account(id: 'bpi', category: AccountCategory.bank, balance: 5000),
          ]);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(mockStorage.saveFinanceDictionary(any)).thenAnswer((_) async {});
      when(mockStorage.saveFinanceCategories(any)).thenAnswer((_) async {});
      when(mockStorage.saveTransactions(any)).thenAnswer((_) async {});
      when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
      when(mockStats.addXp(any)).thenAnswer((_) async {});
      when(mockStats.stats).thenReturn(UserStats.initial());

      presenter = LedgerPresenter(mockStorage, mockStats);
    });

    test('addTransaction increases account balance for inflow', () async {
      await _waitForLoad(presenter);
      await presenter.addTransaction(_txn(
          id: 't1',
          accountId: 'gcash',
          amount: 200,
          type: TransactionType.inflow));
      final gcash = presenter.accounts.firstWhere((a) => a.id == 'gcash');
      expect(gcash.balance, 1200);
    });

    test('addTransaction decreases account balance for outflow', () async {
      await _waitForLoad(presenter);
      await presenter.addTransaction(_txn(
          id: 't1',
          accountId: 'gcash',
          amount: 300,
          type: TransactionType.outflow));
      final gcash = presenter.accounts.firstWhere((a) => a.id == 'gcash');
      expect(gcash.balance, 700);
    });

    test('owed filter surfaces only outstanding reimbursables', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 'owed',
                accountId: 'gcash',
                amount: 800,
                type: TransactionType.outflow,
                month: '2026-03',
                reimbursable: true,
                reimbursementReceivableId: 'r1'),
            _txn(
                id: 'settled',
                accountId: 'gcash',
                amount: 500,
                type: TransactionType.outflow,
                month: '2026-03',
                reimbursable: true,
                reimbursementReceivableId: 'r2'),
            _txn(
                id: 'payback',
                accountId: 'gcash',
                amount: 500,
                type: TransactionType.inflow,
                month: '2026-03',
                receivableId: 'r2'),
            _txn(
                id: 'normal',
                accountId: 'gcash',
                amount: 300,
                type: TransactionType.outflow,
                month: '2026-03'),
          ]);
      await _waitForLoad(presenter);
      presenter.setMonth('2026-03');

      // The settled reimbursable (its payback inflow exists) is excluded.
      expect(presenter.outstandingOwedTotal, 800);
      expect(presenter.hasOutstandingOwed, isTrue);

      presenter.setOwedFilter(true);
      final shown = presenter.groupedTransactions.values
          .expand((list) => list)
          .map((t) => t.id)
          .toList();
      expect(shown, ['owed']);
    });

    test('deleteTransaction reverses balance delta', () async {
      await _waitForLoad(presenter);
      await presenter.addTransaction(_txn(
          id: 't1',
          accountId: 'gcash',
          amount: 400,
          type: TransactionType.outflow));
      await presenter.deleteTransaction('t1');
      final gcash = presenter.accounts.firstWhere((a) => a.id == 'gcash');
      expect(gcash.balance, 1000);
    });

    test('addTransfer creates 2 records with shared transferGroupId', () async {
      await _waitForLoad(presenter);
      final now = DateTime.now();
      await presenter.addTransfer(
        fromAccountId: 'gcash',
        toAccountId: 'bpi',
        amount: 500,
        description: 'Transfer test',
        date: now,
      );
      final txns =
          presenter.groupedTransactions.values.expand((l) => l).toList();
      // All-accounts view now shows BOTH transfer legs (outflow on the source,
      // inflow on the destination) so the destination's increase is visible.
      expect(txns.length, 2);
      expect(txns.map((t) => t.type).toSet(),
          {TransactionType.outflow, TransactionType.inflow});
      expect(txns.map((t) => t.transferGroupId).toSet().length, 1);
      expect(txns.first.transferGroupId, isNotNull);
    });

    test('addTransfer updates balances on both accounts', () async {
      await _waitForLoad(presenter);
      await presenter.addTransfer(
        fromAccountId: 'gcash',
        toAccountId: 'bpi',
        amount: 500,
        description: 'Transfer',
        date: DateTime.now(),
      );
      final gcash = presenter.accounts.firstWhere((a) => a.id == 'gcash');
      final bpi = presenter.accounts.firstWhere((a) => a.id == 'bpi');
      expect(gcash.balance, 500);
      expect(bpi.balance, 5500);
    });

    test('filteredMonthOutflow/Inflow exclude transfer legs', () async {
      final now = DateTime.now();
      final month = toMonthKey(now);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 'spend',
                accountId: 'gcash',
                amount: 200,
                type: TransactionType.outflow,
                month: month,
                categoryId: 'food'),
          ]);
      final fresh = LedgerPresenter(mockStorage, mockStats);
      await _waitForLoad(fresh);
      // A transfer out of gcash into bpi this month.
      await fresh.addTransfer(
        fromAccountId: 'gcash',
        toAccountId: 'bpi',
        amount: 5000,
        description: 'move to savings',
        date: now,
      );

      // Only the genuine 200 spend counts — the 5000 transfer leg is excluded.
      expect(fresh.filteredMonthOutflow, 200);
      expect(fresh.filteredMonthInflow, 0);
    });

    test('addTransfer stamps both legs with the reserved transfer category',
        () async {
      await _waitForLoad(presenter);
      await presenter.addTransfer(
        fromAccountId: 'gcash',
        toAccountId: 'bpi',
        amount: 500,
        description: 'Transfer',
        date: DateTime.now(),
      );
      final legs = presenter.allTransactions
          .where((t) => t.transferGroupId != null)
          .toList();
      expect(legs.length, 2);
      expect(
          legs.every((t) => t.categoryId == FinanceCategory.transferCategoryId),
          isTrue);
      // The reserved category was seeded and is of the transfer type.
      final transferCat = presenter.categories
          .singleWhere((c) => c.id == FinanceCategory.transferCategoryId);
      expect(transferCat.type, CategoryType.transfer);
    });

    test('load() backfills legacy transfer legs onto the transfer category',
        () async {
      // Legs stamped with the old first-expense-category id ('food').
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 'xfer-out',
                accountId: 'gcash',
                amount: 500,
                type: TransactionType.outflow,
                categoryId: 'food',
                transferGroupId: 'g1',
                transferToAccountId: 'bpi'),
            _txn(
                id: 'xfer-in',
                accountId: 'bpi',
                amount: 500,
                type: TransactionType.inflow,
                categoryId: 'food',
                transferGroupId: 'g1'),
            _txn(
                id: 'real',
                accountId: 'gcash',
                amount: 100,
                type: TransactionType.outflow,
                categoryId: 'food'),
          ]);
      final fresh = LedgerPresenter(mockStorage, mockStats);
      await _waitForLoad(fresh);

      final legs = fresh.allTransactions
          .where((t) => t.transferGroupId != null)
          .toList();
      expect(
          legs.every((t) => t.categoryId == FinanceCategory.transferCategoryId),
          isTrue);
      // A genuine expense leg keeps its category.
      expect(fresh.allTransactions.firstWhere((t) => t.id == 'real').categoryId,
          'food');
      verify(mockStorage.saveTransactions(any)).called(greaterThanOrEqualTo(1));
    });

    test('addTransaction awards +25 XP for first-ever transaction', () async {
      await _waitForLoad(presenter);
      await presenter.addTransaction(_txn(
          id: 't1',
          accountId: 'gcash',
          amount: 100,
          type: TransactionType.outflow));
      verify(mockStats.addXp(25)).called(1);
    });

    test('filteredMonthInflow sums inflow for selected month', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'gcash',
                amount: 500,
                type: TransactionType.inflow,
                month: '2026-03'),
            _txn(
                id: 't2',
                accountId: 'gcash',
                amount: 200,
                type: TransactionType.outflow,
                month: '2026-03'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      expect(presenter.filteredMonthInflow, 500);
      expect(presenter.filteredMonthOutflow, 200);
    });

    test('setAccount filters to single-account transactions', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'gcash',
                amount: 100,
                type: TransactionType.outflow,
                month: '2026-03'),
            _txn(
                id: 't2',
                accountId: 'bpi',
                amount: 200,
                type: TransactionType.outflow,
                month: '2026-03'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      presenter.setAccount('gcash');
      final txns =
          presenter.groupedTransactions.values.expand((l) => l).toList();
      expect(txns.length, 1);
      expect(txns.first.accountId, 'gcash');
    });
  });

  // ─── BillsReceivablesPresenter ────────────────────────────────────────────

  group('BillsReceivablesPresenter', () {
    late MockStorageService mockStorage;
    late MockStatsPresenter mockStats;
    late LedgerPresenter ledger;
    late BillsReceivablesPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      when(mockStorage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      mockStats = MockStatsPresenter();

      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'gcash', category: AccountCategory.ewallet, balance: 5000),
          ]);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.saveFinanceCategories(any)).thenAnswer((_) async {});
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(mockStorage.saveFinanceDictionary(any)).thenAnswer((_) async {});
      when(mockStorage.loadBills()).thenAnswer((_) async => []);
      when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(mockStorage.saveBills(any)).thenAnswer((_) async {});
      when(mockStorage.saveReceivables(any)).thenAnswer((_) async {});
      when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
      when(mockStorage.saveTransactions(any)).thenAnswer((_) async {});
      when(mockStats.addXp(any)).thenAnswer((_) async {});
      when(mockStats.stats).thenReturn(UserStats.initial());

      ledger = LedgerPresenter(mockStorage, mockStats);
      presenter = BillsReceivablesPresenter(mockStorage, ledger, mockStats);
    });

    test('bills getter filters by selectedMonth', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', month: '2026-03'),
            _bill(id: 'b2', month: '2026-02'),
          ]);
      await presenter.load();
      presenter..setMonth('2026-03');
      // Use unawaited setMonth result; call getter synchronously
      final bills = presenter.bills;
      expect(bills.map((b) => b.id), contains('b1'));
      expect(bills.any((b) => b.id == 'b2'), isFalse);
    });

    test('totalBillsPending sums unpaid bills', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 300, isPaid: false, month: '2026-03'),
            _bill(id: 'b2', amount: 200, isPaid: true, month: '2026-03'),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-03');
      expect(presenter.totalBillsPending, 300);
    });

    test('markBillPaid marks bill paid and creates outflow transaction',
        () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 500, isPaid: false, month: '2026-03'),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-03');
      await _waitForLoad(ledger);

      await presenter.markBillPaid('b1', paidAmount: 500, accountId: 'gcash');

      final capturedBills =
          verify(mockStorage.saveBills(captureAny)).captured.last as List<Bill>;
      final paidBill = capturedBills.firstWhere((b) => b.id == 'b1');
      expect(paidBill.isPaid, isTrue);
      expect(paidBill.paidAmount, 500);
    });

    test('markBillPaid on a credit-line statement is a transfer, not spend',
        () async {
      // A credit LINE statement (billType is NOT creditCard) whose target is a
      // liability account must still pay down via transfer — deduct the funder,
      // reduce the debt — and never count as a category expense.
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'gcash', category: AccountCategory.ewallet, balance: 5000),
            _account(
                id: 'cl', category: AccountCategory.creditLine, balance: 3000),
          ]);
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(
                id: 'b1',
                amount: 1000,
                month: '2026-03',
                categoryId: 'food',
                billType: BillType.utility, // deliberately NOT creditCard
                accountId: 'cl'),
          ]);
      // Fresh instances so the ledger loads the credit-line account above
      // (setUp's ledger was constructed before this stub override).
      final freshLedger = LedgerPresenter(mockStorage, mockStats);
      final freshBills =
          BillsReceivablesPresenter(mockStorage, freshLedger, mockStats);
      await freshBills.load();
      await freshBills.setMonth('2026-03');
      await _waitForLoad(freshLedger);

      await freshBills.markBillPaid('b1', paidAmount: 1000, accountId: 'gcash');

      // Funder down, liability debt down (it was a transfer).
      expect(freshLedger.accounts.firstWhere((a) => a.id == 'gcash').balance,
          4000);
      expect(
          freshLedger.accounts.firstWhere((a) => a.id == 'cl').balance, 2000);
      // Both legs are transfer-tagged → nothing landed on the 'food' category.
      final legs = freshLedger.allTransactions
          .where((t) => t.transferGroupId != null)
          .toList();
      expect(legs.length, 2);
      expect(
          legs.every((t) => t.categoryId == FinanceCategory.transferCategoryId),
          isTrue);
      expect(
          freshLedger.allTransactions.any((t) =>
              t.categoryId == 'food' && t.type == TransactionType.outflow),
          isFalse);
    });

    test('markBillPaid awards XP when all bills are paid', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 300, isPaid: false, month: '2026-03'),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-03');
      await _waitForLoad(ledger);

      await presenter.markBillPaid('b1', paidAmount: 300, accountId: 'gcash');

      verify(mockStats.addXp(50)).called(1);
    });

    test(
        'markBillPaid with recordInLedger:false flags paid without a transaction',
        () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 500, isPaid: false, month: '2026-03'),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-03');
      await _waitForLoad(ledger);

      // User already logged this expense manually — skip the ledger entirely.
      await presenter.markBillPaid('b1',
          paidAmount: 500, recordInLedger: false);

      final capturedBills =
          verify(mockStorage.saveBills(captureAny)).captured.last as List<Bill>;
      final paidBill = capturedBills.firstWhere((b) => b.id == 'b1');
      expect(paidBill.isPaid, isTrue);
      expect(paidBill.paidAmount, 500);
      // No transaction created and nothing persisted to the ledger.
      expect(paidBill.transactionId, isNull);
      expect(ledger.allTransactions, isEmpty);
      verifyNever(mockStorage.saveTransactions(any));
    });

    test(
        'markReceivableReceived with recordInLedger:false flags received without a transaction',
        () async {
      when(mockStorage.loadReceivables()).thenAnswer((_) async => [
            _receivable(
                id: 'r1', amount: 400, isReceived: false, month: '2026-03'),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-03');
      await _waitForLoad(ledger);

      await presenter.markReceivableReceived('r1',
          receivedAmount: 400, recordInLedger: false);

      final captured = verify(mockStorage.saveReceivables(captureAny))
          .captured
          .last as List<Receivable>;
      final received = captured.firstWhere((r) => r.id == 'r1');
      expect(received.isReceived, isTrue);
      expect(received.receivedAmount, 400);
      expect(received.transactionId, isNull);
      expect(ledger.allTransactions, isEmpty);
      verifyNever(mockStorage.saveTransactions(any));
    });

    test('addBill persists to storage', () async {
      await presenter.load();
      await presenter.setMonth('2026-03');
      await presenter.addBill(_bill(id: 'b_new', month: '2026-03'));
      verify(mockStorage.saveBills(any)).called(greaterThanOrEqualTo(1));
    });

    test('recurring bills auto-generated when navigating to new month',
        () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', month: '2026-02', isRecurring: true),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-02');
      // Navigate to next month — no bills exist yet for March
      await presenter.setMonth('2026-03');

      final capturedBills =
          verify(mockStorage.saveBills(captureAny)).captured.last as List<Bill>;
      final march = capturedBills.where((b) => b.month == '2026-03').toList();
      expect(march.length, 1);
    });

    test('reimbursable expense lifecycle: spawn → settle → cleanup', () async {
      await presenter.load();
      await _waitForLoad(ledger);

      // Expected back NEXT month — the spawned receivable must still surface in
      // the transaction's month (where the debt arose), not be hidden in the
      // payback month, since the receivables getter is month-filtered.
      final expected = DateTime.now().add(const Duration(days: 30));
      final outflow = TransactionRecord(
        id: 'txn-reimb',
        date: DateTime.now(),
        accountId: 'gcash',
        categoryId: 'food',
        amount: 1200,
        type: TransactionType.outflow,
        description: 'Client dinner',
        month: toMonthKey(DateTime.now()),
        reimbursable: true,
        reimbursementReceivableId: 'rcv-reimb',
        owedBy: 'Acme Corp',
      );

      // Spawn: the reimbursable outflow creates a linked receivable whose name
      // surfaces who owes you.
      await ledger.addReimbursableExpense(
        outflow,
        expectedReimbursementDate: expected,
      );
      final spawned =
          presenter.receivables.firstWhere((r) => r.id == 'rcv-reimb');
      expect(spawned.receivableType, ReceivableType.reimbursement);
      expect(spawned.reimbursementForTxnId, 'txn-reimb');
      expect(spawned.amount, 1200);
      expect(spawned.name, contains('Acme Corp'));
      // Bucketed in the outflow's month, not the (next-month) payback date.
      expect(spawned.month, toMonthKey(DateTime.now()));
      expect(spawned.expectedDate, expected);

      // Settle: marking it received writes the offsetting inflow.
      await presenter.markReceivableReceived('rcv-reimb',
          receivedAmount: 1200, accountId: 'gcash');
      final inflow = ledger.allTransactions
          .firstWhere((t) => t.receivableId == 'rcv-reimb');
      expect(inflow.type, TransactionType.inflow);
      expect(inflow.amount, 1200);

      // Cleanup: deleting the outflow tidies up its linked receivable.
      await ledger.deleteTransaction('txn-reimb');
      expect(presenter.receivables.any((r) => r.id == 'rcv-reimb'), isFalse);
    });

    test('editing a reimbursable expense re-syncs its receivable amount',
        () async {
      await presenter.load();
      await _waitForLoad(ledger);

      final outflow = TransactionRecord(
        id: 'txn-edit',
        date: DateTime.now(),
        accountId: 'gcash',
        categoryId: 'food',
        amount: 1000,
        type: TransactionType.outflow,
        description: 'Team lunch',
        month: toMonthKey(DateTime.now()),
        reimbursable: true,
        reimbursementReceivableId: 'rcv-edit',
      );
      await ledger.addReimbursableExpense(
        outflow,
        expectedReimbursementDate: DateTime.now(),
      );
      expect(presenter.receivables.firstWhere((r) => r.id == 'rcv-edit').amount,
          1000);

      // Edit the expense (new amount + name) and re-sync the receivable.
      final edited = outflow.copyWith(amount: 1450, description: 'Team dinner');
      await ledger.updateTransaction(edited);
      await ledger.syncReimbursementReceivable(edited);

      final synced =
          presenter.receivables.firstWhere((r) => r.id == 'rcv-edit');
      expect(synced.amount, 1450);
      expect(synced.name, contains('Team dinner'));
    });

    test('owed total tracks authoritative receivable state, not inflow legs',
        () async {
      await presenter.load();
      await _waitForLoad(ledger);

      // A reimbursable expense with a linked, outstanding receivable.
      final outflow = TransactionRecord(
        id: 'txn-owed',
        date: DateTime.now(),
        accountId: 'gcash',
        categoryId: 'food',
        amount: 800,
        type: TransactionType.outflow,
        description: 'Team lunch',
        month: toMonthKey(DateTime.now()),
        reimbursable: true,
        reimbursementReceivableId: 'rcv-owed',
        owedBy: 'Acme Corp',
      );
      await ledger.addReimbursableExpense(
        outflow,
        expectedReimbursementDate: DateTime.now(),
      );

      // A reimbursable outflow whose receivable was never created (e.g. legacy
      // data or a since-deleted receivable) must NOT count — no receivable
      // means there's nothing still owed.
      await ledger.addTransaction(_txn(
        id: 'txn-orphan',
        accountId: 'gcash',
        amount: 300,
        type: TransactionType.outflow,
        month: toMonthKey(DateTime.now()),
        reimbursable: true,
        reimbursementReceivableId: 'ghost',
      ));

      expect(ledger.outstandingOwedTotal, 800);

      // Marking the receivable received clears the owed even though the payback
      // was recorded outside the ledger (no offsetting inflow leg exists). The
      // old inflow-leg reconstruction would have kept counting it.
      await presenter.markReceivableReceived('rcv-owed',
          receivedAmount: 800, recordInLedger: false);

      expect(ledger.outstandingOwedTotal, 0);
      expect(ledger.hasOutstandingOwed, isFalse);
    });
  });

  // ─── BudgetPresenter ──────────────────────────────────────────────────────

  group('BudgetPresenter', () {
    late MockStorageService mockStorage;
    late MockStatsPresenter mockStats;
    late BudgetPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      when(mockStorage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      mockStats = MockStatsPresenter();
      when(mockStorage.loadBudgets()).thenAnswer((_) async => []);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.loadAccounts()).thenAnswer((_) async => []);
      when(mockStorage.saveBudgets(any)).thenAnswer((_) async {});
      when(mockStorage.loadWarnedBudgetKeys())
          .thenAnswer((_) async => <String>{});
      when(mockStorage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
      when(mockStats.addXp(any)).thenAnswer((_) async {});
      when(mockStats.stats).thenReturn(UserStats.initial());
      presenter = BudgetPresenter(mockStorage, mockStats);
    });

    test('spentFor sums outflow transactions for category in month', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 200,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food'),
            _txn(
                id: 't2',
                accountId: 'a1',
                amount: 150,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food'),
            _txn(
                id: 't3',
                accountId: 'a1',
                amount: 100,
                type: TransactionType.inflow,
                month: '2026-03',
                categoryId: 'food'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      expect(presenter.spentFor('food'), 350);
    });

    test('spentFor excludes transfer legs stamped with an expense category',
        () async {
      // Transfers are committed as an outflow+inflow pair, both carrying the
      // first expense category id ("food"). They must NOT count as spending.
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 200,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food'),
            _txn(
                id: 'xfer-out',
                accountId: 'a1',
                amount: 5000,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food',
                transferGroupId: 'g1',
                transferToAccountId: 'a2'),
            _txn(
                id: 'xfer-in',
                accountId: 'a2',
                amount: 5000,
                type: TransactionType.inflow,
                month: '2026-03',
                categoryId: 'food',
                transferGroupId: 'g1'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      // Only the genuine 200 outflow counts — the 5000 transfer leg is excluded.
      expect(presenter.spentFor('food'), 200);
      expect(presenter.receivedFor('food'), 0);
      expect(presenter.transactionsForCategory('food').length, 1);
    });

    test('spentFor excludes reimbursable outflows (they do not eat the budget)',
        () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 200,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food'),
            _txn(
                id: 'reimb',
                accountId: 'a1',
                amount: 1500,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food',
                reimbursable: true),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      // The reimbursable 1500 is excluded — only the genuine 200 counts.
      expect(presenter.spentFor('food'), 200);
    });

    test('setBudget creates new budget for category', () async {
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => [
            _category(id: 'food', type: CategoryType.expense, name: 'Food'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      await presenter.setBudget('food', 3000);

      final captured = verify(mockStorage.saveBudgets(captureAny)).captured.last
          as List<Budget>;
      expect(
          captured
              .any((b) => b.categoryId == 'food' && b.allocatedAmount == 3000),
          isTrue);
    });

    test('setBudget updates existing budget', () async {
      final existingBudget = Budget(
        id: 'bud1',
        categoryId: 'food',
        month: '2026-03',
        allocatedAmount: 2000,
        group: BudgetGroup.variableOptional,
        budgetType: BudgetType.monthly,
      );
      when(mockStorage.loadBudgets()).thenAnswer((_) async => [existingBudget]);
      await presenter.load();
      presenter.setMonth('2026-03');
      await presenter.setBudget('food', 2500);

      final captured = verify(mockStorage.saveBudgets(captureAny)).captured.last
          as List<Budget>;
      final updated = captured.firstWhere((b) => b.id == 'bud1');
      expect(updated.allocatedAmount, 2500);
    });

    test('isOverBudget returns true when spent > allocated', () async {
      when(mockStorage.loadBudgets()).thenAnswer((_) async => [
            Budget(
              id: 'bud1',
              categoryId: 'food',
              month: '2026-03',
              allocatedAmount: 1000,
              group: BudgetGroup.variableOptional,
              budgetType: BudgetType.monthly,
            ),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 1200,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      expect(presenter.isOverBudget('food'), isTrue);
    });

    test('removeBudget removes budget and saves', () async {
      when(mockStorage.loadBudgets()).thenAnswer((_) async => [
            Budget(
              id: 'bud1',
              categoryId: 'food',
              month: '2026-03',
              allocatedAmount: 1000,
              group: BudgetGroup.variableOptional,
              budgetType: BudgetType.monthly,
            ),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      await presenter.removeBudget('food');

      final captured = verify(mockStorage.saveBudgets(captureAny)).captured.last
          as List<Budget>;
      expect(captured.any((b) => b.categoryId == 'food'), isFalse);
    });
  });

  // ─── TreasuryHistoryPresenter ─────────────────────────────────────────────

  group('TreasuryHistoryPresenter', () {
    late MockStorageService mockStorage;
    late TreasuryHistoryPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      when(mockStorage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => []);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.loadBills()).thenAnswer((_) async => []);
      when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
      when(mockStorage.loadAccounts()).thenAnswer((_) async => []);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.saveMonthlySummaries(any)).thenAnswer((_) async {});
      presenter = TreasuryHistoryPresenter(mockStorage);
    });

    test('summaries are sorted descending by month', () async {
      when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => [
            _summary('2026-01'),
            _summary('2026-03'),
            _summary('2026-02'),
          ]);
      await presenter.load();
      final months = presenter.summaries.map((s) => s.month).toList();
      expect(months, ['2026-03', '2026-02', '2026-01']);
    });

    test('closePreviousMonthIfNeeded is idempotent', () async {
      final lastMonth = previousMonth(toMonthKey(DateTime.now()));
      when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => [
            _summary(lastMonth),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 100,
                type: TransactionType.outflow,
                month: lastMonth),
          ]);
      await presenter.load();
      // saveMonthlySummaries should NOT be called since month is already closed
      verifyNever(mockStorage.saveMonthlySummaries(any));
    });

    test('closePreviousMonthIfNeeded skips when no data exists for prior month',
        () async {
      // No bills, transactions, or receivables for prior month → no summary created
      await presenter.load();
      verifyNever(mockStorage.saveMonthlySummaries(any));
    });

    test('closePreviousMonthIfNeeded creates summary for prior month with data',
        () async {
      final lastMonth = previousMonth(toMonthKey(DateTime.now()));
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 500,
                type: TransactionType.inflow,
                month: lastMonth),
          ]);
      await presenter.load();
      verify(mockStorage.saveMonthlySummaries(any)).called(1);
    });

    test('currentMonthSummary computes live data for current month', () async {
      final currentMonth = toMonthKey(DateTime.now());
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'a1', category: AccountCategory.ewallet, balance: 2000),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 1000,
                type: TransactionType.inflow,
                month: currentMonth),
            _txn(
                id: 't2',
                accountId: 'a1',
                amount: 300,
                type: TransactionType.outflow,
                month: currentMonth),
          ]);
      await presenter.load();
      final summary = presenter.currentMonthSummary;
      expect(summary?.totalInflow, 1000);
      expect(summary?.totalOutflow, 300);
      expect(summary?.netSavings, 700);
    });

    test(
        'savings contribution counts transfers into pockets, nets withdrawals, '
        'and ignores income/spending', () async {
      final currentMonth = toMonthKey(DateTime.now());
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'cash', category: AccountCategory.ewallet),
            _account(id: 'save', category: AccountCategory.savings),
            _account(id: 'goal', category: AccountCategory.goal),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            // Real income — must NOT count as a contribution.
            _txn(
                id: 'inc',
                accountId: 'cash',
                amount: 10000,
                type: TransactionType.inflow,
                month: currentMonth),
            // ₱5000 moved cash → savings (the pocket inflow leg counts).
            _txn(
                id: 'to-save-out',
                accountId: 'cash',
                amount: 5000,
                type: TransactionType.outflow,
                month: currentMonth,
                transferGroupId: 'g1',
                transferToAccountId: 'save'),
            _txn(
                id: 'to-save-in',
                accountId: 'save',
                amount: 5000,
                type: TransactionType.inflow,
                month: currentMonth,
                transferGroupId: 'g1'),
            // ₱1000 pulled back out of savings — a withdrawal, nets against it.
            _txn(
                id: 'from-save-out',
                accountId: 'save',
                amount: 1000,
                type: TransactionType.outflow,
                month: currentMonth,
                transferGroupId: 'g2',
                transferToAccountId: 'cash'),
            _txn(
                id: 'from-save-in',
                accountId: 'cash',
                amount: 1000,
                type: TransactionType.inflow,
                month: currentMonth,
                transferGroupId: 'g2'),
            // ₱2000 moved cash → goal.
            _txn(
                id: 'to-goal-out',
                accountId: 'cash',
                amount: 2000,
                type: TransactionType.outflow,
                month: currentMonth,
                transferGroupId: 'g3',
                transferToAccountId: 'goal'),
            _txn(
                id: 'to-goal-in',
                accountId: 'goal',
                amount: 2000,
                type: TransactionType.inflow,
                month: currentMonth,
                transferGroupId: 'g3'),
          ]);
      await presenter.load();

      // Net set aside = 5000 in − 1000 out + 2000 goal = 6000.
      expect(presenter.monthlySavingsContribution(currentMonth), 6000);
      expect(presenter.currentMonthSummary?.savingsContribution, 6000);

      // Per-pocket breakdown, richest first.
      final pockets = presenter.savingsContributionByPocket(currentMonth);
      expect(pockets.map((p) => p.accountId), ['save', 'goal']);
      expect(pockets.firstWhere((p) => p.accountId == 'save').amount, 4000);
      expect(pockets.firstWhere((p) => p.accountId == 'goal').amount, 2000);

      // The cash-flow surplus is unaffected by the field (income − expense).
      // Income 10000, no real expenses → net savings 10000.
      expect(presenter.currentMonthSummary?.netSavings, 10000);
    });

    test(
        'repairTransferPollutedSummariesOnce recomputes transfer-inflated '
        'months while preserving frozen net-worth fields', () async {
      // A stored summary closed by an earlier build: a 5000 transfer was
      // counted as both income and Food & Drinks spending.
      final polluted = MonthlySummary(
        month: '2026-03',
        totalInflow: 15000, // real 10000 + 5000 transfer-in leg
        totalOutflow: 9000, // real 4000 + 5000 transfer-out leg
        totalBills: 0,
        totalBillsPaid: 0,
        billCount: 0,
        billsPaidCount: 0,
        totalReceivables: 0,
        totalReceived: 0,
        receivableCount: 0,
        netSavings: 6000,
        endingCash: 12345, // frozen month-end snapshot — must be preserved
        accountSnapshots: const {'a1': 999},
        netWorth: 50000, // frozen — must be preserved
        categorySpend: const {'food': 9000}, // real 4000 + 5000 transfer
      );
      when(mockStorage.loadMonthlySummaries())
          .thenAnswer((_) async => [polluted]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 'real-out',
                accountId: 'a1',
                amount: 4000,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food'),
            _txn(
                id: 'real-in',
                accountId: 'a1',
                amount: 10000,
                type: TransactionType.inflow,
                month: '2026-03',
                categoryId: 'salary'),
            _txn(
                id: 'xfer-out',
                accountId: 'a1',
                amount: 5000,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food',
                transferGroupId: 'g1',
                transferToAccountId: 'a2'),
            _txn(
                id: 'xfer-in',
                accountId: 'a2',
                amount: 5000,
                type: TransactionType.inflow,
                month: '2026-03',
                categoryId: 'food',
                transferGroupId: 'g1'),
          ]);
      await presenter.load();

      final fixed = presenter.summaries.firstWhere((s) => s.month == '2026-03');
      // Transfer-derived inflation removed.
      expect(fixed.totalInflow, 10000);
      expect(fixed.totalOutflow, 4000);
      expect(fixed.netSavings, 6000);
      expect(fixed.categorySpend['food'], 4000);
      // Frozen month-end snapshot fields are untouched.
      expect(fixed.endingCash, 12345);
      expect(fixed.netWorth, 50000);
      expect(fixed.accountSnapshots, const {'a1': 999});
      // The corrected summaries were persisted.
      verify(mockStorage.saveMonthlySummaries(any)).called(1);
    });

    test('repairTransferPollutedSummariesOnce leaves clean months untouched',
        () async {
      // Spreadsheet-imported month: authoritative figures, no transaction rows.
      final clean = MonthlySummary(
        month: '2026-02',
        totalInflow: 54097,
        totalOutflow: 43580,
        totalBills: 0,
        totalBillsPaid: 0,
        billCount: 0,
        billsPaidCount: 0,
        totalReceivables: 0,
        totalReceived: 0,
        receivableCount: 0,
        netSavings: 10517,
        endingCash: 0,
        accountSnapshots: const {},
        categorySpend: const {'food': 2481},
      );
      when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => [clean]);
      await presenter.load();

      final after = presenter.summaries.firstWhere((s) => s.month == '2026-02');
      expect(after.totalInflow, 54097);
      expect(after.categorySpend['food'], 2481);
      // No transfer legs in any month → nothing rewritten.
      verifyNever(mockStorage.saveMonthlySummaries(any));
    });
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

MonthlySummary _summary(String month) => MonthlySummary(
      month: month,
      totalInflow: 0,
      totalOutflow: 0,
      totalBills: 0,
      totalBillsPaid: 0,
      billCount: 0,
      billsPaidCount: 0,
      totalReceivables: 0,
      totalReceived: 0,
      receivableCount: 0,
      netSavings: 0,
      endingCash: 0,
      accountSnapshots: {},
      categorySpend: {},
    );

/// Waits for [presenter]'s initial load() to complete.
Future<void> _waitForLoad(LedgerPresenter presenter) async {
  while (presenter.isLoading) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
}
