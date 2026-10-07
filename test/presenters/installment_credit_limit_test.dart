import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/credit_cycle.dart';
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

      // Mark 1 month paid:
      // The 1,000 monthly slice moves into current balance (currentPayable = 1000),
      // and unbilledInstallments drops to 9000.
      // totalDebt remains 10,000, availableCredit remains 40,000.
      await presenter.markPaid('i1');

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

  group('InstallmentPresenter due dates and shared form logic', () {
    late MockStorageService mockStorage;
    late MockStatsPresenter mockStats;
    late LedgerPresenter ledger;
    late InstallmentPresenter presenter;

    FinancialAccount card(
      String id, {
      int? statementDay,
      int? dueDay,
      int? daysAfter,
      AccountCategory category = AccountCategory.creditCard,
    }) =>
        FinancialAccount(
          id: id,
          name: id.toUpperCase(),
          category: category,
          balance: 0,
          creditLimit: 100000,
          statementDay: statementDay,
          paymentDueDay: dueDay,
          dueDaysAfterStatement: daysAfter,
          colorHex: '#FFFFFF',
          icon: 'card',
        );

    // Closes the 20th, due 15 days later (Maya-style "days after statement").
    final maya = card('maya',
        statementDay: 20, daysAfter: 15, category: AccountCategory.creditLine);
    // Closes the 20th, due the 10th (fixed day of month).
    final bpi = card('bpi', statementDay: 20, dueDay: 10);
    // Closes the 15th, due 15 days later: Jan 30, then Mar 2 (skips Feb).
    final midMonth = card('mid', statementDay: 15, daysAfter: 15);
    // Closes the 28th, due the 5th: the close sits on February's last day.
    final lateClose = card('late', statementDay: 28, dueDay: 5);
    // No statement day: a bare due day, clamped to the month's length.
    final bnpl = card('bnpl', dueDay: 30, category: AccountCategory.bnpl);

    var storedInstallments = <Installment>[];

    Installment plan(String accountId,
            {String startMonth = '2026-11',
            String? categoryId,
            DateTime? purchaseDate,
            int deferralMonths = 0,
            double interestRate = 0}) =>
        Installment(
          id: 'p-$accountId',
          name: 'Phone',
          accountId: accountId,
          totalAmount: 12000,
          monthlyAmount: 1000,
          totalMonths: 12,
          startMonth: startMonth,
          categoryId: categoryId,
          purchaseDate: purchaseDate,
          deferralMonths: deferralMonths,
          interestRate: interestRate,
        );

    setUp(() async {
      mockStorage = MockStorageService();
      mockStats = MockStatsPresenter();
      storedInstallments = [];
      var accounts = <FinancialAccount>[maya, bpi, midMonth, lateClose, bnpl];
      var txns = <TransactionRecord>[];

      when(mockStorage.loadAccounts()).thenAnswer((_) async => accounts);
      when(mockStorage.saveAccounts(any)).thenAnswer((inv) async {
        accounts = List<FinancialAccount>.from(inv.positionalArguments[0]);
      });
      when(mockStorage.loadTransactions()).thenAnswer((_) async => txns);
      when(mockStorage.saveTransactions(any)).thenAnswer((inv) async {
        txns = List<TransactionRecord>.from(inv.positionalArguments[0]);
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
      await ledger.load();
      await presenter.load();
    });

    group('dueDate', () {
      test(
          'days-after rule: the statement DUE in the month, not the one '
          'closing in it', () {
        // Bought Oct 19 → Oct 20 statement, due Nov 4 → startMonth 2026-11.
        final inst = plan('maya', startMonth: '2026-11');
        presenter.setMonth('2026-11');
        expect(presenter.dueDate(inst), DateTime(2026, 11, 4));
        expect(presenter.dueLabel(inst), 'Due Nov 4');

        // The next payment rides the Nov 20 statement, due Dec 5.
        presenter.setMonth('2026-12');
        expect(presenter.dueDate(inst), DateTime(2026, 12, 5));
      });

      test('days-after rule across the year end', () {
        final inst = plan('maya', startMonth: '2026-12');
        presenter.setMonth('2027-01');
        // Dec 20 close + 15 days → Jan 4.
        expect(presenter.dueDate(inst), DateTime(2027, 1, 4));
      });

      test('days-after rule landing on a month end', () {
        final inst = plan('mid', startMonth: '2026-01');
        presenter.setMonth('2026-01');
        // Jan 15 close + 15 days → Jan 30.
        expect(presenter.dueDate(inst), DateTime(2026, 1, 30));

        // Feb 15 + 15 days is Mar 2: no statement falls due in February.
        presenter.setMonth('2026-02');
        expect(presenter.dueDate(inst), isNull);
        expect(presenter.dueLabel(inst), isNull);

        // March gets two (Mar 2 and Mar 30) — the later statement wins.
        presenter.setMonth('2026-03');
        expect(presenter.dueDate(inst), DateTime(2026, 3, 30));
      });

      test('fixed due-day rule on a billing cycle', () {
        final inst = plan('bpi', startMonth: '2026-11');
        presenter.setMonth('2026-11');
        expect(presenter.dueDate(inst), DateTime(2026, 11, 10));
        presenter.setMonth('2027-01');
        expect(presenter.dueDate(inst), DateTime(2027, 1, 10));
      });

      test('fixed due-day rule with a close on the 28th (February end)', () {
        final inst = plan('late', startMonth: '2026-03');
        presenter.setMonth('2026-03');
        // Feb 28 close → due Mar 5.
        expect(presenter.dueDate(inst), DateTime(2026, 3, 5));
      });

      test('bare due day without a cycle clamps to the month length', () {
        final inst = plan('bnpl', startMonth: '2026-01');
        presenter.setMonth('2026-02');
        expect(presenter.dueDate(inst), DateTime(2026, 2, 28));
        presenter.setMonth('2026-04');
        expect(presenter.dueDate(inst), DateTime(2026, 4, 30));
      });

      test("the due date agrees with the start month's cycle", () {
        // Whatever month the plan starts in, its first due date is the due
        // date of the cycle the purchase landed on.
        for (final day in [1, 19, 20, 21, 31]) {
          final bought = DateTime(2026, 10, day);
          final start = calculateInstallmentStartMonth(maya, bought);
          presenter.setMonth(start);
          expect(presenter.dueDate(plan('maya', startMonth: start)),
              maya.cycleContaining(bought)!.due,
              reason: 'bought Oct $day');
        }
      });
    });

    group('interestPreview', () {
      test('null for 0% or no principal', () {
        expect(presenter.interestPreview(principal: 12000, months: 12, rate: 0),
            isNull);
        expect(presenter.interestPreview(principal: null, months: 12, rate: 1),
            isNull);
      });

      test('computed add-on payment when no monthly amount is given', () {
        final p =
            presenter.interestPreview(principal: 12000, months: 12, rate: 1)!;
        expect(p.totalPayable, 13440);
        expect(p.totalInterest, 1440);
        expect(p.label, contains('(1%/mo)'));
      });

      test('honours a manually edited monthly amount', () {
        // The bank quoted ₱1,200/mo — totals must follow what is saved.
        final p = presenter.interestPreview(
            principal: 12000, months: 12, rate: 1, monthlyAmount: 1200)!;
        expect(p.totalPayable, 14400);
        expect(p.totalInterest, 2400);
        expect(p.label, contains('Total payable: ₱14,400.00'));
      });

      test('formats a fractional rate without trailing zeros', () {
        final p = presenter.interestPreview(
            principal: 10000, months: 10, rate: 1.25)!;
        expect(p.label, contains('(1.25%/mo)'));
      });
    });

    group('buildInstallment', () {
      test('editing without a category keeps the existing one', () {
        final existing = plan('maya', categoryId: 'tech');
        final edited = presenter.buildInstallment(
          existing: existing,
          name: '  Phone 2 ',
          accountId: 'maya',
          totalAmount: 12000,
          monthlyAmount: 1000,
          totalMonths: 12,
          startMonth: '2026-11',
          purchaseDate: DateTime(2026, 10, 19),
          note: '  ',
        );
        expect(edited.id, existing.id);
        expect(edited.categoryId, 'tech');
        expect(edited.name, 'Phone 2');
        expect(edited.note, isNull);
      });

      test('passing a null category clears it; a new plan gets an id', () {
        final cleared = presenter.buildInstallment(
          existing: plan('maya', categoryId: 'tech'),
          name: 'Phone',
          accountId: 'maya',
          totalAmount: 12000,
          monthlyAmount: 1000,
          totalMonths: 12,
          startMonth: '2026-11',
          purchaseDate: DateTime(2026, 10, 19),
          categoryId: null,
        );
        expect(cleared.categoryId, isNull);

        final fresh = presenter.buildInstallment(
          name: 'Laptop',
          accountId: 'bpi',
          totalAmount: 6000,
          monthlyAmount: 1000,
          totalMonths: 6,
          startMonth: '2026-11',
          purchaseDate: DateTime(2026, 10, 1),
          categoryId: 'tech',
          note: 'promo',
        );
        expect(fresh.id, isNotEmpty);
        expect(fresh.categoryId, 'tech');
        expect(fresh.note, 'promo');
        expect(fresh.isActive, isTrue);
      });

      test('saveInstallment updates in place on edit', () async {
        final existing = plan('maya', categoryId: 'tech');
        await presenter.saveInstallment(existing, isEdit: false);
        final edited = presenter.buildInstallment(
          existing: existing,
          name: 'Phone',
          accountId: 'maya',
          totalAmount: 12000,
          monthlyAmount: 1000,
          totalMonths: 12,
          startMonth: presenter.suggestedStartMonth(
              accountId: 'maya',
              purchaseDate: DateTime(2026, 10, 19),
              deferralMonths: 2),
          purchaseDate: DateTime(2026, 10, 19),
          deferralMonths: 2,
        );
        await presenter.saveInstallment(edited, isEdit: true);
        expect(storedInstallments, hasLength(1));
        expect(storedInstallments.single.startMonth, '2027-01');
        expect(storedInstallments.single.categoryId, 'tech');
      });
    });

    test('detailLine lists account, purchase, deferral, interest and due', () {
      presenter.setMonth('2027-01');
      final inst = plan('maya',
          startMonth: '2027-01',
          purchaseDate: DateTime(2026, 10, 19),
          deferralMonths: 2,
          interestRate: 1.5);
      expect(presenter.detailLine(inst),
          'MAYA · Bought Oct 19 · Deferred 2 mos · 1.5%/mo int · Due Jan 4');
      expect(presenter.deferralLabel(plan('maya', deferralMonths: 1)),
          'Deferred 1 mo');
      expect(presenter.purchasedLabel(plan('maya')), isNull);
    });
  });
}
