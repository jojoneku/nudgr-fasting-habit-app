import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/credit_cycle.dart';
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

      // Verify installment purchase transaction in ledger with isInstallment: true
      expect(ledger.allTransactions.length, 1);
      final txn = ledger.allTransactions.first;
      expect(txn.isInstallment, isTrue);
      expect(txn.installmentId, 'inst-phone');
      expect(txn.amount, 12000.0);
      // But no instant cash outflow in monthly expenses
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
      expect(ledger.allTransactions.length, 2); // 1 purchase + 1 payment
      final paymentTxn =
          ledger.allTransactions.firstWhere((t) => !t.isInstallment);
      expect(paymentTxn.categoryId, 'cat-tech');
      expect(paymentTxn.amount, 2000.0);
      expect(paymentTxn.accountId, 'maribank');
      expect(paymentTxn.installmentId, 'inst-phone');

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

      // Verify purchase transaction is recorded with isInstallment: true
      expect(ledger.allTransactions.length, 1);
      expect(ledger.allTransactions.first.isInstallment, isTrue);
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

    test('installment with interest calculates monthly payment and totals', () {
      final monthly = Installment.computeMonthlyAmount(
        principal: 10000.0,
        months: 10,
        monthlyRate: 1.5,
      );
      expect(monthly, 1150.0); // 1000 principal + 150 interest per month

      final inst = Installment(
        id: 'inst-interest',
        name: 'Laptop with Interest',
        accountId: 'shopeepay',
        totalAmount: 10000.0,
        monthlyAmount: monthly,
        totalMonths: 10,
        startMonth: '2026-10',
        interestRate: 1.5,
      );

      expect(inst.hasInterest, isTrue);
      expect(inst.monthlyInterest, 150.0);
      expect(inst.totalInterest, 1500.0);
      expect(inst.totalPayable, 11500.0);
    });

    test(
        'FinanceActionsExecutor (Nudgy chat) proposes, executes addInstallment and queries findInstallments',
        () async {
      await ledger.load();
      await installments.load();
      await bills.load();
      // Built the way TreasuryPresenters builds it. Without a budget presenter
      // the executor has no categories to bind "Technology" against, and the
      // plan would silently land uncategorised.
      final budget = BudgetPresenter(
          mockStorage, mockStats, ledger, mockNotifications, null, bills);
      await budget.load();

      final executor = FinanceActionsExecutor(
        bills: bills,
        budget: budget,
        ledger: ledger,
        installments: installments,
      );
      final purchased = DateTime.now().subtract(const Duration(days: 2));
      final purchasedIso = '${purchased.year}-'
          '${purchased.month.toString().padLeft(2, '0')}-'
          '${purchased.day.toString().padLeft(2, '0')}';

      // 1. Querying findInstallments before adding returns empty
      final emptyRead = await executor.runRead(const AiToolCall(
        id: 'read-1',
        name: 'findInstallments',
        input: {'query': 'laptop'},
      ));
      expect(emptyRead.ok, isTrue);
      expect(emptyRead.summary.contains('No installments matched'), isTrue);

      // 2. Propose addInstallment via chat
      final proposeFuture = executor.propose(AiToolCall(
        id: 'call-1',
        name: 'addInstallment',
        input: {
          'name': 'Gaming Laptop',
          'amount': 30000.0,
          'months': 6,
          'account': 'ShopeePay',
          'interestRate': 1.5,
          'category': 'Technology',
          'date': purchasedIso,
          'note': 'Work & gaming laptop',
        },
      ));

      // Verify pending proposal card
      expect(executor.pending, isNotNull);
      final pending = executor.pending!;
      String detail(String label) =>
          pending.details.firstWhere((d) => d.label == label).value;
      expect(pending.title, contains('Gaming Laptop'));
      expect(pending.details.any((d) => d.label == 'Monthly payment'), isTrue);
      expect(pending.details.any((d) => d.label == 'Interest rate'), isTrue);
      // The card names what will be saved, not what the model typed.
      expect(detail('Account'), 'ShopeePay BNPL');
      expect(detail('Category'), 'Technology');
      expect(detail('Purchase date'), purchasedIso);

      // 3. User confirms proposal card
      await executor.confirm();
      final result = await proposeFuture;
      expect(result.ok, isTrue);
      expect(result.summary, contains('Added installment purchase'));

      // 4. Verify installment created
      expect(installments.installments.length, 1);
      final inst = installments.installments.first;
      expect(inst.name, 'Gaming Laptop');
      expect(inst.totalAmount, 30000.0);
      expect(inst.totalMonths, 6);
      expect(inst.interestRate, 1.5);
      expect(inst.monthlyAmount, 5450.0); // 5000 + 450/mo interest
      expect(inst.accountId, 'shopeepay');
      expect(inst.categoryId, 'cat-tech');
      expect(inst.note, 'Work & gaming laptop');

      // 5. Verify ledger transaction stamped
      expect(ledger.allTransactions.length, 1);
      final txn = ledger.allTransactions.first;
      expect(txn.description, 'Gaming Laptop');
      expect(txn.amount, 30000.0);
      expect(txn.isInstallment, isTrue);
      expect(txn.installmentId, inst.id);
      expect(txn.accountId, 'shopeepay');
      expect(txn.categoryId, 'cat-tech');
      expect(ledger.filteredMonthOutflow, 0.0); // no instant cash drain

      // 6. Verify credit limit held
      final acct = ledger.accounts.firstWhere((a) => a.id == 'shopeepay');
      expect(acct.unbilledInstallments, 32700.0); // 6 * 5450

      // 7. Querying findInstallments after adding returns the row
      final foundRead = await executor.runRead(const AiToolCall(
        id: 'read-2',
        name: 'findInstallments',
        input: {'query': 'laptop'},
      ));
      expect(foundRead.ok, isTrue);
      expect(foundRead.summary, contains('Gaming Laptop'));
      expect(foundRead.summary, contains('5450/mo'));
      // Plans are not scoped to a month, so the summary must not claim one.
      expect(foundRead.summary, startsWith('1 installments in any month'));

      // 8. The purchase record is listed but not counted as spending: the
      // plan's monthly payments are. Counting it would add the principal on
      // top of every payment.
      final txnRead = await executor.runRead(const AiToolCall(
        id: 'read-3',
        name: 'findTransactions',
        input: {'query': 'laptop'},
      ));
      expect(txnRead.summary, contains('Spent ₱0'));
      expect(txnRead.summary, contains('installment purchase'));
      expect(txnRead.summary, contains('Technology · ShopeePay BNPL'));
    });

    test(
        'findTransactions counts an installment plan\'s payments, not its '
        'purchase record', () async {
      await ledger.load();
      await installments.load();
      await bills.load();
      final executor = FinanceActionsExecutor(
        bills: bills,
        ledger: ledger,
        installments: installments,
      );

      await ledger.addInstallmentPurchase(Installment(
        id: 'inst-phone',
        name: 'iPhone on SPayLater',
        accountId: 'shopeepay',
        totalAmount: 12000.0,
        monthlyAmount: 2000.0,
        totalMonths: 6,
        startMonth: '2026-10',
        purchaseDate: DateTime(2026, 10, 2),
        categoryId: 'cat-tech',
      ));
      installments.setMonth('2026-10');
      await installments.markPaid('inst-phone', fundingAccountId: 'maribank');

      final result = await executor.runRead(const AiToolCall(
        id: 'read-1',
        name: 'findTransactions',
        input: {'query': 'iphone'},
      ));

      expect(result.summary, contains('2 transactions'));
      // ₱2000 paid, not ₱14000 (principal + payment).
      expect(result.summary, contains('Spent ₱2000'));
      expect(result.summary, contains('1 installment purchase is listed'));
      final purchaseRow =
          result.summary.split('\n').singleWhere((l) => l.contains('₱12000'));
      expect(purchaseRow, contains('installment purchase, not counted'));
    });

    group('deleting an installment purchase', () {
      Installment plan(String id) => Installment(
            id: id,
            name: 'Fuse holder $id',
            accountId: 'shopeepay',
            totalAmount: 300.0,
            monthlyAmount: 100.0,
            totalMonths: 3,
            startMonth: '2026-10',
            purchaseDate: DateTime(2026, 9, 6),
          );

      String purchaseIdOf(String planId) => ledger.allTransactions
          .firstWhere((t) => t.installmentId == planId && t.isInstallment)
          .id;

      Future<void> loadAll() async {
        await ledger.load();
        await installments.load();
        await bills.load();
      }

      test('bulk delete removes the plan, so it stops holding credit',
          () async {
        await loadAll();
        await ledger.addInstallmentPurchase(plan('a'));
        await ledger.addInstallmentPurchase(plan('b'));
        expect(
            ledger.accounts
                .firstWhere((a) => a.id == 'shopeepay')
                .unbilledInstallments,
            600.0);

        await ledger.deleteTransactions({purchaseIdOf('a')});

        expect(installments.allInstallments.map((i) => i.id), ['b']);
        expect(installmentsState.map((i) => i.id), ['b']);
        expect(
            ledger.accounts
                .firstWhere((a) => a.id == 'shopeepay')
                .unbilledInstallments,
            300.0);
      });

      test('bulk delete takes the plan payments with it, and Undo restores all',
          () async {
        await loadAll();
        await ledger.addInstallmentPurchase(plan('a'));
        installments.setMonth('2026-10');
        await installments.markPaid('a', fundingAccountId: 'maribank');
        final bankAfterPay =
            ledger.accounts.firstWhere((a) => a.id == 'maribank').balance;
        expect(bankAfterPay, 49900.0);

        final removed = await ledger.deleteTransactions({purchaseIdOf('a')});

        expect(removed, hasLength(2));
        expect(ledger.allTransactions, isEmpty);
        expect(ledger.accounts.firstWhere((a) => a.id == 'maribank').balance,
            50000.0);

        await ledger.restoreTransactions(removed);

        expect(installments.allInstallments.map((i) => i.id), ['a']);
        expect(installments.paidCount('a'), 1);
        expect(ledger.accounts.firstWhere((a) => a.id == 'maribank').balance,
            bankAfterPay);
        expect(
            ledger.accounts
                .firstWhere((a) => a.id == 'shopeepay')
                .unbilledInstallments,
            200.0);
      });

      test('single delete then Undo brings the plan back', () async {
        await loadAll();
        await ledger.addInstallmentPurchase(plan('a'));

        final removed =
            await ledger.deleteTransactionOrGroup(purchaseIdOf('a'));
        expect(installments.allInstallments, isEmpty);
        expect(
            ledger.accounts
                .firstWhere((a) => a.id == 'shopeepay')
                .unbilledInstallments,
            0.0);

        await ledger.restoreTransactions(removed);

        expect(installments.allInstallments.map((i) => i.id), ['a']);
        expect(
            ledger.accounts
                .firstWhere((a) => a.id == 'shopeepay')
                .unbilledInstallments,
            300.0);
      });
    });

    group('editing an installment purchase', () {
      Installment plan({int deferralMonths = 0}) => Installment(
            id: 'a',
            name: 'Fuse holder',
            accountId: 'shopeepay',
            totalAmount: 300.0,
            monthlyAmount: 100.0,
            totalMonths: 3,
            startMonth: deferralMonths == 0 ? '2026-10' : '2026-12',
            purchaseDate: DateTime(2026, 9, 6),
            deferralMonths: deferralMonths,
            categoryId: 'cat-tech',
          );

      TransactionRecord purchase() => ledger.allTransactions
          .firstWhere((t) => t.installmentId == 'a' && t.isInstallment);

      double balanceOf(String id) =>
          ledger.accounts.firstWhere((a) => a.id == id).balance;

      double holdOf(String id) =>
          ledger.accounts.firstWhere((a) => a.id == id).unbilledInstallments;

      /// Purchase of 300 over 3 months with the first payment made from the
      /// bank — the state the bug wiped on edit.
      Future<void> purchaseWithOnePayment({int deferralMonths = 0}) async {
        await ledger.load();
        await installments.load();
        await bills.load();
        await ledger
            .addInstallmentPurchase(plan(deferralMonths: deferralMonths));
        installments.setMonth('2026-10');
        await installments.markPaid('a', fundingAccountId: 'maribank');
      }

      Future<void> saveForm({
        double amount = 300.0,
        int months = 3,
        DateTime? date,
        String accountId = 'shopeepay',
        String description = 'Fuse holder',
      }) =>
          ledger.saveInstallmentPurchase(
            existing: purchase(),
            accountId: accountId,
            amount: amount,
            months: months,
            interestRate: 0.0,
            date: date ?? DateTime(2026, 9, 6),
            description: description,
            note: '',
            categoryId: 'cat-tech',
          );

      test('keeps the plan, its payments and the paid count', () async {
        await purchaseWithOnePayment(deferralMonths: 2);
        final purchaseId = purchase().id;

        await saveForm(description: 'Fuse holder (pair)');

        expect(installments.allInstallments, hasLength(1));
        final edited = installments.allInstallments.single;
        expect(edited.id, 'a');
        expect(edited.name, 'Fuse holder (pair)');
        // Fields the form doesn't edit survive.
        expect(edited.deferralMonths, 2);
        expect(edited.startMonth, '2026-12');
        expect(edited.isActive, isTrue);
        expect(edited.monthlyAmount, 100.0);
        expect(installments.paidCount('a'), 1);
        expect(ledger.allTransactions, hasLength(2));
        expect(purchase().id, purchaseId);
        expect(purchase().description, 'Fuse holder (pair)');
        expect(balanceOf('maribank'), 49900.0);
        expect(holdOf('shopeepay'), 200.0);
        expect(installmentsState.single.name, 'Fuse holder (pair)');
      });

      test('changing the amount re-prices the plan and the hold', () async {
        await purchaseWithOnePayment();

        await saveForm(amount: 600.0);

        final edited = installments.allInstallments.single;
        expect(edited.totalAmount, 600.0);
        expect(edited.monthlyAmount, 200.0);
        expect(installments.paidCount('a'), 1);
        // Two payments left at the new monthly amount.
        expect(holdOf('shopeepay'), 400.0);
        expect(purchase().amount, 600.0);
        expect(purchase().isInstallment, isTrue);
        // A purchase record never touches the card balance itself.
        expect(balanceOf('shopeepay'), 0.0);
        expect(balanceOf('maribank'), 49900.0);
      });

      test('moving the purchase date reschedules, keeping the deferral',
          () async {
        await purchaseWithOnePayment(deferralMonths: 1);
        final moved = DateTime(2026, 11, 20);

        await saveForm(date: moved);

        final edited = installments.allInstallments.single;
        expect(edited.purchaseDate, moved);
        expect(edited.deferralMonths, 1);
        expect(
          edited.startMonth,
          calculateInstallmentStartMonth(shopeePay, moved, deferralMonths: 1),
        );
        expect(purchase().month, '2026-11');
        expect(installments.paidCount('a'), 1);
      });

      test('turning the split off removes the plan and books the debt once',
          () async {
        await purchaseWithOnePayment();
        final old = purchase();

        await ledger.convertInstallmentPurchaseToRegular(TransactionRecord(
          id: old.id,
          date: old.date,
          accountId: 'shopeepay',
          categoryId: 'cat-tech',
          amount: 300.0,
          type: TransactionType.outflow,
          description: old.description,
          month: old.month,
        ));

        expect(installments.allInstallments, isEmpty);
        expect(installmentsState, isEmpty);
        final regular =
            ledger.allTransactions.firstWhere((t) => t.id == old.id);
        expect(regular.isInstallment, isFalse);
        expect(regular.installmentId, isNull);
        expect(holdOf('shopeepay'), 0.0);
        // The 100 paid from the bank was real cash: it stays out of the bank
        // and now pays the card down, as a transfer — not spending.
        expect(balanceOf('maribank'), 49900.0);
        expect(balanceOf('shopeepay'), 200.0);
        final legs = ledger.allTransactions
            .where((t) => t.transferGroupId != null)
            .toList();
        expect(legs, hasLength(2));
        expect(legs.every((t) => t.installmentId == null), isTrue);
        expect(legs.map((t) => t.accountId).toSet(), {'maribank', 'shopeepay'});
        expect(ledger.allTransactions, hasLength(3));
      });

      test('turning the split off drops months already charged to the card',
          () async {
        await ledger.load();
        await installments.load();
        await bills.load();
        await ledger.addInstallmentPurchase(plan());
        installments.setMonth('2026-10');
        await installments.markPaid('a'); // charged to the card itself
        expect(balanceOf('shopeepay'), 100.0);
        final old = purchase();

        await ledger.convertInstallmentPurchaseToRegular(TransactionRecord(
          id: old.id,
          date: old.date,
          accountId: 'shopeepay',
          categoryId: 'cat-tech',
          amount: 300.0,
          type: TransactionType.outflow,
          description: old.description,
          month: old.month,
        ));

        // The full 300 covers that month: owed once, not 400.
        expect(ledger.allTransactions, hasLength(1));
        expect(balanceOf('shopeepay'), 300.0);
        expect(holdOf('shopeepay'), 0.0);
      });

      test('converting a regular expense reverses its balance exactly once',
          () async {
        await ledger.load();
        await installments.load();
        await bills.load();
        final regular = TransactionRecord(
          id: 'txn-monitor',
          date: DateTime(2026, 10, 2),
          accountId: 'shopeepay',
          categoryId: 'cat-tech',
          amount: 6000.0,
          type: TransactionType.outflow,
          description: 'New Monitor',
          month: '2026-10',
        );
        await ledger.addTransaction(regular);
        expect(balanceOf('shopeepay'), 6000.0);

        await ledger.saveInstallmentPurchase(
          existing: regular,
          accountId: 'shopeepay',
          amount: 6000.0,
          months: 3,
          interestRate: 0.0,
          date: regular.date,
          description: regular.description,
          categoryId: 'cat-tech',
        );

        expect(ledger.allTransactions, hasLength(1));
        final converted = ledger.allTransactions.single;
        expect(converted.id, 'txn-monitor');
        expect(converted.isInstallment, isTrue);
        expect(balanceOf('shopeepay'), 0.0);
        expect(holdOf('shopeepay'), 6000.0);
        expect(installments.allInstallments, hasLength(1));
        expect(installments.allInstallments.single.id, converted.installmentId);
        expect(installments.allInstallments.single.monthlyAmount, 2000.0);
      });

      test('an inline grid edit carries the plan along', () async {
        await purchaseWithOnePayment();

        final applied =
            await ledger.updateRecordInline(purchase().copyWith(amount: 900.0));

        expect(applied, isTrue);
        final edited = installments.allInstallments.single;
        expect(edited.totalAmount, 900.0);
        expect(edited.monthlyAmount, 300.0);
        expect(installments.paidCount('a'), 1);
        expect(holdOf('shopeepay'), 600.0);
      });

      test('an inline move to a non-credit account is refused', () async {
        await purchaseWithOnePayment();

        final applied = await ledger
            .updateRecordInline(purchase().copyWith(accountId: 'maribank'));

        expect(applied, isFalse);
        expect(purchase().accountId, 'shopeepay');
        expect(installments.allInstallments.single.accountId, 'shopeepay');
        expect(balanceOf('maribank'), 49900.0);
      });
    });

    group('deleting a plan is single-pass', () {
      Future<void> purchaseWithTwoPayments() async {
        await ledger.load();
        await installments.load();
        await bills.load();
        await ledger.addInstallmentPurchase(Installment(
          id: 'a',
          name: 'Fuse holder',
          accountId: 'shopeepay',
          totalAmount: 300.0,
          monthlyAmount: 100.0,
          totalMonths: 3,
          startMonth: '2026-10',
          purchaseDate: DateTime(2026, 9, 6),
        ));
        installments.setMonth('2026-10');
        await installments.markPaid('a', fundingAccountId: 'maribank');
        installments.setMonth('2026-11');
        await installments.markPaid('a', fundingAccountId: 'maribank');
        expect(ledger.allTransactions, hasLength(3));
        clearInteractions(mockStorage);
      }

      test('from the plan: one ledger save, one plan save', () async {
        await purchaseWithTwoPayments();

        await installments.deleteInstallment('a');

        verify(mockStorage.saveTransactions(any)).called(1);
        verify(mockStorage.saveInstallments(any)).called(1);
        expect(ledger.allTransactions, isEmpty);
        expect(installmentsState, isEmpty);
        expect(ledger.accounts.firstWhere((a) => a.id == 'maribank').balance,
            50000.0);
      });

      test('from the purchase record: one ledger save, one plan save',
          () async {
        await purchaseWithTwoPayments();
        final purchaseId =
            ledger.allTransactions.firstWhere((t) => t.isInstallment).id;

        await ledger.deleteTransaction(purchaseId);

        verify(mockStorage.saveTransactions(any)).called(1);
        verify(mockStorage.saveInstallments(any)).called(1);
        expect(ledger.allTransactions, isEmpty);
        expect(installments.allInstallments, isEmpty);
        expect(
            ledger.accounts
                .firstWhere((a) => a.id == 'shopeepay')
                .unbilledInstallments,
            0.0);
      });
    });
  });
}
