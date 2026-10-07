import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../mocks.mocks.dart';

void main() {
  group('Installment unbilled amount calculations', () {
    final inst = Installment(
      id: 'inst-1',
      name: 'Phone',
      accountId: 'bpi-card',
      totalAmount: 12000,
      monthlyAmount: 1000,
      totalMonths: 12,
      startMonth: '2026-01',
    );

    test('calculates paidCount, remainingMonths, and remainingAmount', () {
      final txns = [
        TransactionRecord(
          id: 't1',
          date: DateTime(2026, 1, 15),
          accountId: 'bpi-card',
          categoryId: '__installment__',
          amount: 1000,
          type: TransactionType.outflow,
          description: 'Payment 1',
          month: '2026-01',
          installmentId: 'inst-1',
        ),
        TransactionRecord(
          id: 't2',
          date: DateTime(2026, 2, 15),
          accountId: 'bpi-card',
          categoryId: '__installment__',
          amount: 1000,
          type: TransactionType.outflow,
          description: 'Payment 2',
          month: '2026-02',
          installmentId: 'inst-1',
        ),
      ];

      expect(inst.paidCount(txns), 2);
      expect(inst.remainingMonths(txns), 10);
      expect(inst.remainingAmount(txns), 10000.0);
    });

    test('totalUnbilledForAccount sums across active installments for account',
        () {
      final inst2 = Installment(
        id: 'inst-2',
        name: 'Laptop',
        accountId: 'bpi-card',
        totalAmount: 20000,
        monthlyAmount: 5000,
        totalMonths: 4,
        startMonth: '2026-01',
      );
      final instOther = Installment(
        id: 'inst-3',
        name: 'Watch',
        accountId: 'other-card',
        totalAmount: 5000,
        monthlyAmount: 1000,
        totalMonths: 5,
        startMonth: '2026-01',
      );

      final total = Installment.totalUnbilledForAccount(
        'bpi-card',
        [inst, inst2, instOther],
        [],
      );
      expect(total, 32000.0);
    });
  });

  group('FinancialAccount installment debt and availableCredit', () {
    test(
        'availableCredit deducts totalDebt (currentPayable + unbilledInstallments)',
        () {
      final account = FinancialAccount(
        id: 'cc',
        name: 'BPI Madness',
        category: AccountCategory.creditCard,
        balance: 2000,
        creditLimit: 50000,
        unbilledInstallments: 10000,
        colorHex: '#FFFFFF',
        icon: 'card',
      );

      expect(account.currentPayable, 2000.0);
      expect(account.totalDebt, 12000.0);
      expect(account.availableCredit, 38000.0);
      expect(account.utilization, 12000.0 / 50000.0);
    });

    test(
        'overpaid card with unbilled installments still respects limit ceiling',
        () {
      final account = FinancialAccount(
        id: 'cc',
        name: 'BPI',
        category: AccountCategory.creditCard,
        balance: -2000, // overpaid
        creditLimit: 50000,
        unbilledInstallments: 5000,
        colorHex: '#FFFFFF',
        icon: 'card',
      );

      expect(account.currentPayable, 0.0);
      expect(account.totalDebt, 5000.0);
      expect(account.availableCredit, 45000.0);
    });
  });

  group('InstallmentPresenter account filtering and integration', () {
    late MockStorageService mockStorage;
    late MockStatsPresenter mockStats;
    late LedgerPresenter ledger;
    late InstallmentPresenter presenter;

    final creditCard = FinancialAccount(
      id: 'cc',
      name: 'Credit Card',
      category: AccountCategory.creditCard,
      balance: 0,
      creditLimit: 50000,
      statementDay: 15,
      paymentDueDay: 5,
      colorHex: '#FFFFFF',
      icon: 'card',
    );
    final bnpl = FinancialAccount(
      id: 'bnpl',
      name: 'SpayLater',
      category: AccountCategory.bnpl,
      balance: 0,
      creditLimit: 10000,
      paymentDueDay: 15,
      colorHex: '#FFFFFF',
      icon: 'card',
    );
    final savings = FinancialAccount(
      id: 'savings',
      name: 'BPI Savings',
      category: AccountCategory.savings,
      balance: 100000,
      colorHex: '#FFFFFF',
      icon: 'piggy',
    );
    final bank = FinancialAccount(
      id: 'bank',
      name: 'Checking',
      category: AccountCategory.bank,
      balance: 50000,
      colorHex: '#FFFFFF',
      icon: 'bank',
    );

    var storedAccounts = <FinancialAccount>[];
    var storedInstallments = <Installment>[];
    var storedTxns = <TransactionRecord>[];

    setUp(() {
      mockStorage = MockStorageService();
      mockStats = MockStatsPresenter();
      storedAccounts = [creditCard, bnpl, savings, bank];
      storedInstallments = [];
      storedTxns = [];

      when(mockStorage.loadAccounts()).thenAnswer((_) async => storedAccounts);
      when(mockStorage.saveAccounts(any)).thenAnswer((inv) async {
        storedAccounts =
            List<FinancialAccount>.from(inv.positionalArguments[0]);
      });
      when(mockStorage.loadTransactions()).thenAnswer((_) async => storedTxns);
      when(mockStorage.saveTransactions(any)).thenAnswer((inv) async {
        storedTxns = List<TransactionRecord>.from(inv.positionalArguments[0]);
      });
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.saveFinanceCategories(any)).thenAnswer((_) async {});
      when(mockStorage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(mockStorage.saveFinanceDictionary(any)).thenAnswer((_) async {});
      when(mockStorage.loadInstallments())
          .thenAnswer((_) async => storedInstallments);
      when(mockStorage.saveInstallments(any)).thenAnswer((inv) async {
        storedInstallments = List<Installment>.from(inv.positionalArguments[0]);
      });
      when(mockStorage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
      when(mockStorage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
      when(mockStats.addXp(any)).thenAnswer((_) async {});
      when(mockStats.awardStat(any)).thenAnswer((_) async {});
      when(mockStats.stats).thenReturn(UserStats.initial());

      ledger = LedgerPresenter(mockStorage, mockStats);
      presenter = InstallmentPresenter(mockStorage, ledger, mockStats);
    });

    test('creditAccounts filters out non-liability accounts', () async {
      await ledger.load();
      await presenter.load();

      final eligible = presenter.creditAccounts;
      expect(eligible.map((a) => a.id).toList(), ['cc', 'bnpl']);
      expect(
          eligible.any((a) => a.category == AccountCategory.savings), isFalse);
      expect(eligible.any((a) => a.category == AccountCategory.bank), isFalse);
    });

    test('dueDate and dueLabel resolve against paymentDueDay', () async {
      await ledger.load();
      await presenter.load();
      presenter.setMonth('2026-10');

      final inst = Installment(
        id: 'i1',
        name: 'Phone',
        accountId: 'cc',
        totalAmount: 10000,
        monthlyAmount: 1000,
        totalMonths: 10,
        startMonth: '2026-10',
      );

      final date = presenter.dueDate(inst);
      expect(date, DateTime(2026, 10, 5));
      expect(presenter.dueLabel(inst), 'Due Oct 5');
    });

    test(
        'adding installment deducts full remaining amount from availableCredit immediately',
        () async {
      await ledger.load();
      await presenter.load();
      presenter.setMonth('2026-10');

      var card = ledger.accounts.firstWhere((a) => a.id == 'cc');
      expect(card.availableCredit, 50000.0);
      expect(card.unbilledInstallments, 0.0);

      final newInst = Installment(
        id: 'i1',
        name: 'Phone',
        accountId: 'cc',
        totalAmount: 10000,
        monthlyAmount: 1000,
        totalMonths: 10,
        startMonth: '2026-10',
      );
      await presenter.addInstallment(newInst);

      card = ledger.accounts.firstWhere((a) => a.id == 'cc');
      expect(card.unbilledInstallments, 10000.0);
      expect(card.currentPayable, 0.0);
      expect(card.totalDebt, 10000.0);
      expect(card.availableCredit, 40000.0);

      // The statement closes and bills month 1 onto the card (the charge the
      // statement generator posts; "Mark paid" is not offered on a card with a
      // billing cycle). The 1,000 monthly slice moves into current balance
      // (currentPayable = 1000), and unbilledInstallments drops to 9000.
      // totalDebt remains 10,000, availableCredit remains 40,000.
      await ledger.postSystemTransactions([
        newInst.chargeRecord(
          recordId: newInst.chargeId(1),
          number: 1,
          date: DateTime(2026, 10, 15),
          month: '2026-10',
          categoryId: kInstallmentCategoryId,
        ),
      ]);

      card = ledger.accounts.firstWhere((a) => a.id == 'cc');
      expect(card.currentPayable, 1000.0);
      expect(card.unbilledInstallments, 9000.0);
      expect(card.totalDebt, 10000.0);
      expect(card.availableCredit, 40000.0);

      // Paying down the credit card balance via transfer settles currentPayable:
      await ledger.addTransfer(
        fromAccountId: 'bank',
        toAccountId: 'cc',
        amount: 1000,
        description: 'Pay CC Statement',
        date: DateTime(2026, 10, 20),
      );

      card = ledger.accounts.firstWhere((a) => a.id == 'cc');
      expect(card.currentPayable, 0.0);
      expect(card.unbilledInstallments, 9000.0);
      expect(card.totalDebt, 9000.0);
      expect(card.availableCredit, 41000.0);
    });

    test('interestLabel formats integer and fractional rates, null for 0%', () {
      final zero = Installment(
        id: 'z',
        name: 'Promo',
        accountId: 'cc',
        totalAmount: 10000,
        monthlyAmount: 1000,
        totalMonths: 10,
        startMonth: '2026-10',
        interestRate: 0.0,
      );
      final intRate = Installment(
        id: 'r1',
        name: 'Card Loan',
        accountId: 'cc',
        totalAmount: 10000,
        monthlyAmount: 1100,
        totalMonths: 10,
        startMonth: '2026-10',
        interestRate: 1.0,
      );
      final fracRate = Installment(
        id: 'r2',
        name: 'BNPL',
        accountId: 'cc',
        totalAmount: 10000,
        monthlyAmount: 1150,
        totalMonths: 10,
        startMonth: '2026-10',
        interestRate: 1.5,
      );

      expect(presenter.interestLabel(zero), isNull);
      expect(presenter.interestLabel(intRate), '1%/mo int');
      expect(presenter.interestLabel(fracRate), '1.5%/mo int');
    });
  });
}
