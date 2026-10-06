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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Installment Ledger & Consolidated Statements Integration', () {
    late MockStorageService mockStorage;
    late MockStatsPresenter mockStats;
    late MockNotificationService mockNotifications;
    late LedgerPresenter ledger;
    late InstallmentPresenter installments;
    late BillsReceivablesPresenter bills;

    final techCategory = FinanceCategory(
      id: 'cat-tech',
      name: 'Technology',
      colorHex: '#3366FF',
      icon: 'devices',
      type: CategoryType.expense,
    );

    final shopeePay = FinancialAccount(
      id: 'shopeepay',
      name: 'ShopeePay BNPL',
      category: AccountCategory.bnpl,
      balance: 0.0,
      creditLimit: 20000.0,
      statementDay: 1,
      paymentDueDay: 15,
      colorHex: '#EE4D2D',
      icon: 'wallet',
    );

    final bank = FinancialAccount(
      id: 'maribank',
      name: 'MariBank',
      category: AccountCategory.bank,
      balance: 50000.0,
      colorHex: '#123456',
      icon: 'bank',
    );

    late List<FinancialAccount> accountsState;
    late List<TransactionRecord> transactionsState;
    late List<Installment> installmentsState;
    late List<Bill> billsState;
    late Set<String> dismissedStatementKeysState;

    setUp(() {
      mockStorage = MockStorageService();
      mockStats = MockStatsPresenter();
      mockNotifications = MockNotificationService();

      accountsState = [shopeePay, bank];
      transactionsState = [];
      installmentsState = [];
      billsState = [];
      dismissedStatementKeysState = {};

      when(mockStorage.loadAccounts()).thenAnswer((_) async => accountsState);
      when(mockStorage.saveAccounts(any)).thenAnswer((inv) async {
        accountsState =
            List<FinancialAccount>.from(inv.positionalArguments.first as List);
      });

      when(mockStorage.loadFinanceCategories())
          .thenAnswer((_) async => [techCategory]);
      when(mockStorage.saveFinanceCategories(any)).thenAnswer((_) async {});

      when(mockStorage.loadTransactions())
          .thenAnswer((_) async => transactionsState);
      when(mockStorage.saveTransactions(any)).thenAnswer((inv) async {
        transactionsState =
            List<TransactionRecord>.from(inv.positionalArguments.first as List);
      });

      when(mockStorage.loadInstallments())
          .thenAnswer((_) async => installmentsState);
      when(mockStorage.saveInstallments(any)).thenAnswer((inv) async {
        installmentsState =
            List<Installment>.from(inv.positionalArguments.first as List);
      });

      when(mockStorage.loadBills()).thenAnswer((_) async => billsState);
      when(mockStorage.saveBills(any)).thenAnswer((inv) async {
        billsState = List<Bill>.from(inv.positionalArguments.first as List);
      });

      when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
      when(mockStorage.saveReceivables(any)).thenAnswer((_) async {});
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(mockStorage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(mockStorage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
      when(mockStorage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
      when(mockStorage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(mockStorage.saveNotificationPreferences(any))
          .thenAnswer((_) async {});

      when(mockStorage.loadDismissedStatementKeys())
          .thenAnswer((_) async => dismissedStatementKeysState);
      when(mockStorage.saveDismissedStatementKeys(any)).thenAnswer((inv) async {
        dismissedStatementKeysState =
            Set<String>.from(inv.positionalArguments.first as Set);
      });

      when(mockStats.addXp(any)).thenAnswer((_) async {});
      when(mockStats.awardStat(any)).thenAnswer((_) async {});
      when(mockStats.stats).thenReturn(UserStats.initial());

      ledger = LedgerPresenter(mockStorage, mockStats);
      installments = InstallmentPresenter(mockStorage, ledger, mockStats);
      bills = BillsReceivablesPresenter(
        mockStorage,
        ledger,
        mockStats,
        notifications: mockNotifications,
        installments: installments,
        clock: () => DateTime(2026, 10, 5),
      );
    });

    test(
        'addInstallmentPurchase preserves category and holds credit limit without inflating monthly cash spend',
        () async {
      await ledger.load();
      await installments.load();
      await bills.load();

      final inst = Installment(
        id: 'inst-phone',
        name: 'iPhone on SPayLater',
        accountId: 'shopeepay',
        totalAmount: 12000.0,
        monthlyAmount: 2000.0,
        totalMonths: 6,
        startMonth: '2026-10',
        purchaseDate: DateTime(2026, 10, 2),
        categoryId: 'cat-tech',
      );

      await ledger.addInstallmentPurchase(inst);

      // Verify installment saved with categoryId
      expect(installments.installments.length, 1);
      final savedInst = installments.installments.first;
      expect(savedInst.id, 'inst-phone');
      expect(savedInst.categoryId, 'cat-tech');

      // Verify credit hold on liability account
      final acct = ledger.accounts.firstWhere((a) => a.id == 'shopeepay');
      expect(acct.unbilledInstallments, 12000.0);
      expect(acct.availableCredit, 8000.0); // 20k - 12k

      // Verify no instant cash expense in ledger
      expect(ledger.allTransactions.isEmpty, isTrue);
      expect(ledger.filteredMonthOutflow, 0.0);
    });

    test('marking installment paid inherits categoryId and tags installmentId',
        () async {
      await ledger.load();
      await installments.load();
      await bills.load();

      final inst = Installment(
        id: 'inst-phone',
        name: 'iPhone on SPayLater',
        accountId: 'shopeepay',
        totalAmount: 12000.0,
        monthlyAmount: 2000.0,
        totalMonths: 6,
        startMonth: '2026-10',
        purchaseDate: DateTime(2026, 10, 2),
        categoryId: 'cat-tech',
      );
      await ledger.addInstallmentPurchase(inst);

      // Mark the current month installment paid from MariBank
      await installments.markPaid('inst-phone', fundingAccountId: 'maribank');

      // Verify transaction inherits category 'cat-tech' and funding account deducted
      expect(ledger.allTransactions.length, 1);
      final txn = ledger.allTransactions.first;
      expect(txn.categoryId, 'cat-tech');
      expect(txn.amount, 2000.0);
      expect(txn.accountId, 'maribank');
      expect(txn.installmentId, 'inst-phone');

      // Verify unbilled installments decreased
      final acct = ledger.accounts.firstWhere((a) => a.id == 'shopeepay');
      expect(acct.unbilledInstallments, 10000.0);
    });

    test(
        'deleting an auto-generated statement bill persists to dismissedStatementKeys and prevents regeneration',
        () async {
      await ledger.load();
      await installments.load();
      await bills.load();

      final inst = Installment(
        id: 'inst-phone',
        name: 'iPhone on SPayLater',
        accountId: 'shopeepay',
        totalAmount: 12000.0,
        monthlyAmount: 2000.0,
        totalMonths: 6,
        startMonth: '2026-10',
        purchaseDate: DateTime(2026, 10, 2),
        categoryId: 'cat-tech',
      );
      await ledger.addInstallmentPurchase(inst);

      // Month is 2026-10. Calling setMonth generates statement
      await bills.setMonth('2026-10');

      final generated =
          bills.bills.where((b) => b.billType == BillType.creditCard).toList();
      expect(generated.length, 1);
      expect(generated.first.accountId, 'shopeepay');
      expect(generated.first.amount,
          2000.0); // includes installment due this month

      // User deletes the auto statement bill
      await bills.deleteBill(generated.first.id);

      // Verify it was marked in dismissed keys
      expect(dismissedStatementKeysState.contains('shopeepay|2026-10'), isTrue);
      expect(
          bills.bills.where((b) => b.billType == BillType.creditCard).isEmpty,
          isTrue);

      // Switching months or re-running setMonth does NOT resurrect it
      await bills.setMonth('2026-11');
      await bills.setMonth('2026-10');

      expect(
          bills.bills.where((b) => b.billType == BillType.creditCard).isEmpty,
          isTrue);
    });

    test(
        'converting an existing regular outflow transaction to installment reverses revolving debt and holds installment credit',
        () async {
      await ledger.load();
      await installments.load();
      await bills.load();

      // 1. Initial state: regular transaction logged on ShopeePay
      final initialTxn = TransactionRecord(
        id: 'txn-existing',
        date: DateTime(2026, 10, 2),
        accountId: 'shopeepay',
        categoryId: 'cat-tech',
        amount: 6000.0,
        type: TransactionType.outflow,
        description: 'New Monitor',
        month: '2026-10',
      );
      await ledger.addTransaction(initialTxn);

      // Verify regular transaction impacts
      expect(ledger.allTransactions.length, 1);
      expect(ledger.filteredMonthOutflow, 6000.0);
      var acct = ledger.accounts.firstWhere((a) => a.id == 'shopeepay');
      expect(acct.balance, 6000.0);
      expect(acct.unbilledInstallments, 0.0);
      expect(acct.availableCredit, 14000.0);

      // 2. User edits and converts to 3-month installment
      // The conversion workflow reverses the existing transaction & logs installment
      await ledger.deleteTransaction(initialTxn.id);

      final convertedInst = Installment(
        id: 'inst-converted',
        name: initialTxn.description,
        accountId: initialTxn.accountId,
        totalAmount: initialTxn.amount,
        monthlyAmount: 2000.0,
        totalMonths: 3,
        startMonth: '2026-10',
        purchaseDate: initialTxn.date,
        categoryId: initialTxn.categoryId,
      );
      await ledger.addInstallmentPurchase(convertedInst);

      // Verify transaction removed from ledger & monthly outflow
      expect(ledger.allTransactions.isEmpty, isTrue);
      expect(ledger.filteredMonthOutflow, 0.0);

      // Verify liability account debt moved from revolving balance to unbilled installments
      acct = ledger.accounts.firstWhere((a) => a.id == 'shopeepay');
      expect(acct.balance, 0.0); // revolving balance reversed
      expect(acct.unbilledInstallments,
          6000.0); // credit limit held by installment
      expect(acct.availableCredit, 14000.0); // 20k - 6k installment hold

      // Verify installment retained category
      expect(installments.installments.length, 1);
      expect(installments.installments.first.categoryId, 'cat-tech');

      // 3. Generating statement bill for 2026-10 bills only 2000.0 (first installment) instead of full 6000.0
      await bills.setMonth('2026-10');
      final statement = bills.bills.firstWhere(
        (b) => b.billType == BillType.creditCard && b.accountId == 'shopeepay',
      );
      expect(statement.amount, 2000.0);
    });
  });
}
