import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/utils/credit_cycle.dart';
import 'package:intl/intl.dart';

void main() {
  group('Installment model purchaseDate and deferralMonths', () {
    test(
        'serializes and deserializes purchaseDate and deferralMonths correctly',
        () {
      final purchaseDate = DateTime(2026, 10, 25);
      final installment = Installment(
        id: 'inst-101',
        name: 'iPhone 18 Pro',
        accountId: 'bpi-card',
        totalAmount: 72000,
        monthlyAmount: 3000,
        totalMonths: 24,
        startMonth: '2027-02',
        purchaseDate: purchaseDate,
        deferralMonths: 2,
        note: '24 months 0% interest, deferred 2 months',
      );

      final json = installment.toJson();
      expect(json['purchaseDate'], purchaseDate.toIso8601String());
      expect(json['deferralMonths'], 2);

      final roundTrip = Installment.fromJson(json);
      expect(roundTrip.purchaseDate, purchaseDate);
      expect(roundTrip.deferralMonths, 2);
      expect(roundTrip.name, 'iPhone 18 Pro');
      expect(roundTrip.startMonth, '2027-02');
    });

    test(
        'backward compatibility: legacy JSON without purchaseDate is null and deferralMonths is 0',
        () {
      final legacyJson = {
        'id': 'legacy-1',
        'name': 'MacBook Pro',
        'accountId': 'card-1',
        'totalAmount': 100000.0,
        'monthlyAmount': 8333.33,
        'totalMonths': 12,
        'startMonth': '2026-05',
        'isActive': true,
      };

      final parsed = Installment.fromJson(legacyJson);
      expect(parsed.purchaseDate, isNull);
      expect(parsed.deferralMonths, 0);
      expect(parsed.interestRate, 0.0);
      expect(parsed.hasInterest, isFalse);
      expect(parsed.name, 'MacBook Pro');
    });

    test('copyWith preserves and updates deferralMonths and interestRate', () {
      final original = Installment(
        id: 'inst-1',
        name: 'Desk',
        accountId: 'card-1',
        totalAmount: 12000,
        monthlyAmount: 1000,
        totalMonths: 12,
        startMonth: '2026-02',
        purchaseDate: DateTime(2026, 1, 15),
        deferralMonths: 1,
        interestRate: 0.5,
      );

      final modified = original.copyWith(deferralMonths: 3, interestRate: 1.5);
      expect(modified.deferralMonths, 3);
      expect(modified.interestRate, 1.5);
      expect(modified.purchaseDate, DateTime(2026, 1, 15));

      final preserved = original.copyWith(name: 'Standing Desk');
      expect(preserved.deferralMonths, 1);
      expect(preserved.interestRate, 0.5);
      expect(preserved.name, 'Standing Desk');
    });
  });

  group('Installment interest calculation logic', () {
    test(
        '0% promo defaults: hasInterest is false, totalPayable equals totalAmount',
        () {
      final promo = Installment(
        id: 'p1',
        name: '0% Promo Phone',
        accountId: 'card-1',
        totalAmount: 24000,
        monthlyAmount: 2000,
        totalMonths: 12,
        startMonth: '2026-01',
      );

      expect(promo.hasInterest, isFalse);
      expect(promo.monthlyInterest, 0.0);
      expect(promo.totalInterest, 0.0);
      expect(promo.totalPayable, 24000.0);
      expect(
        Installment.computeMonthlyAmount(
          principal: 24000,
          months: 12,
          monthlyRate: 0.0,
        ),
        2000.0,
      );
    });

    test(
        'monthly add-on rate computes monthly payment, total interest, and total payable',
        () {
      // ₱12,000 across 12 months at 1.0%/mo:
      // Monthly principal: ₱1,000
      // Monthly interest: ₱12,000 * 0.01 = ₱120
      // Monthly payment: ₱1,120
      // Total interest: ₱1,440
      // Total payable: ₱13,440
      final inst = Installment(
        id: 'i1',
        name: 'Computer',
        accountId: 'card-1',
        totalAmount: 12000,
        monthlyAmount: 1120,
        totalMonths: 12,
        startMonth: '2026-01',
        interestRate: 1.0,
      );

      expect(inst.hasInterest, isTrue);
      expect(inst.monthlyInterest, 120.0);
      expect(inst.totalInterest, 1440.0);
      expect(inst.totalPayable, 13440.0);
      expect(
        Installment.computeMonthlyAmount(
          principal: 12000,
          months: 12,
          monthlyRate: 1.0,
        ),
        1120.0,
      );
    });

    test('fractional interest rates compute correctly', () {
      // ₱20,000 across 10 months at 1.5%/mo:
      // Monthly principal: ₱2,000
      // Monthly interest: ₱20,000 * 0.015 = ₱300
      // Monthly payment: ₱2,300
      final inst = Installment(
        id: 'i2',
        name: 'Appliance',
        accountId: 'bnpl-1',
        totalAmount: 20000,
        monthlyAmount: 2300,
        totalMonths: 10,
        startMonth: '2026-01',
        interestRate: 1.5,
      );

      expect(inst.hasInterest, isTrue);
      expect(inst.monthlyInterest, 300.0);
      expect(inst.totalInterest, 3000.0);
      expect(inst.totalPayable, 23000.0);
      expect(
        Installment.computeMonthlyAmount(
          principal: 20000,
          months: 10,
          monthlyRate: 1.5,
        ),
        2300.0,
      );
    });

    test('toJson omits interestRate if 0, includes if > 0', () {
      final zero = Installment(
        id: 'z',
        name: 'Zero',
        accountId: 'c',
        totalAmount: 1000,
        monthlyAmount: 100,
        totalMonths: 10,
        startMonth: '2026-01',
        interestRate: 0.0,
      );
      expect(zero.toJson().containsKey('interestRate'), isFalse);

      final withInt = Installment(
        id: 'w',
        name: 'With Interest',
        accountId: 'c',
        totalAmount: 1000,
        monthlyAmount: 110,
        totalMonths: 10,
        startMonth: '2026-01',
        interestRate: 1.0,
      );
      expect(withInt.toJson()['interestRate'], 1.0);
    });
  });

  group('calculateInstallmentStartMonth credit cycle logic', () {
    final bpiCard = FinancialAccount(
      id: 'bpi',
      name: 'BPI Visa',
      category: AccountCategory.creditCard,
      balance: 0,
      colorHex: '#B71C1C',
      icon: 'credit_card',
      statementDay: 20,
      paymentDueDay: 10, // Due 10th of following month
    );

    final mayaCredit = FinancialAccount(
      id: 'maya',
      name: 'Maya Credit',
      category: AccountCategory.creditLine,
      balance: 0,
      colorHex: '#00C853',
      icon: 'account_balance_wallet',
      statementDay: 20,
      dueDaysAfterStatement:
          15, // 15 days after 20th -> due ~5th of following month
    );

    final cashAccount = FinancialAccount(
      id: 'cash',
      name: 'Cash Wallet',
      category: AccountCategory.cash,
      balance: 5000,
      colorHex: '#4CAF50',
      icon: 'payments',
    );

    test(
        'purchase on or before statement cut-off falls into current cycle statement and due date',
        () {
      // Statement day is 20th. Purchase is on Oct 15 (before cut-off).
      // Statement closes Oct 20 -> due Nov 10 -> startMonth is '2026-11'
      final purchaseDate = DateTime(2026, 10, 15);
      final startMonth = calculateInstallmentStartMonth(bpiCard, purchaseDate);
      expect(startMonth, '2026-11');
    });

    test('purchase on the exact statement cut-off day falls into current cycle',
        () {
      // Purchase is on Oct 20 (on cut-off day).
      // Statement closes Oct 20 -> due Nov 10 -> startMonth is '2026-11'
      final purchaseDate = DateTime(2026, 10, 20);
      final startMonth = calculateInstallmentStartMonth(bpiCard, purchaseDate);
      expect(startMonth, '2026-11');
    });

    test(
        'purchase after statement cut-off rolls to next statement cycle and its due date',
        () {
      // Statement day is 20th. Purchase is on Oct 21 (after cut-off).
      // Rolls to Nov 20 statement -> due Dec 10 -> startMonth is '2026-12'
      final purchaseDate = DateTime(2026, 10, 21);
      final startMonth = calculateInstallmentStartMonth(bpiCard, purchaseDate);
      expect(startMonth, '2026-12');
    });

    test(
        'handles year-end boundary when purchase rolls over to January next year',
        () {
      // Statement day 20th. Purchase on Dec 25.
      // Rolls to Jan 20, 2027 statement -> due Feb 10, 2027 -> startMonth is '2027-02'
      final purchaseDate = DateTime(2026, 12, 25);
      final startMonth = calculateInstallmentStartMonth(bpiCard, purchaseDate);
      expect(startMonth, '2027-02');
    });

    test('relative days-after-statement accounts compute correct due month',
        () {
      // Maya: closes 20th, due 15 days after.
      // Purchase on Oct 19: closes Oct 20, due Nov 4 -> '2026-11'
      expect(calculateInstallmentStartMonth(mayaCredit, DateTime(2026, 10, 19)),
          '2026-11');

      // Purchase on Oct 21: closes Nov 20, due Dec 5 -> '2026-12'
      expect(calculateInstallmentStartMonth(mayaCredit, DateTime(2026, 10, 21)),
          '2026-12');
    });

    test('deferred payment shifts start month by 1, 2, or 3 months', () {
      // Oct 21 purchase on BPI Visa: normally due Dec 2026 ('2026-12').
      final purchaseDate = DateTime(2026, 10, 21);

      // Deferral 1 month -> due Jan 2027 ('2027-01')
      expect(
        calculateInstallmentStartMonth(bpiCard, purchaseDate,
            deferralMonths: 1),
        '2027-01',
      );

      // Deferral 2 months -> due Feb 2027 ('2027-02')
      expect(
        calculateInstallmentStartMonth(bpiCard, purchaseDate,
            deferralMonths: 2),
        '2027-02',
      );

      // Deferral 3 months -> due Mar 2027 ('2027-03')
      expect(
        calculateInstallmentStartMonth(bpiCard, purchaseDate,
            deferralMonths: 3),
        '2027-03',
      );
    });

    test('deferred payment across year boundaries computes correct start month',
        () {
      // Purchase Oct 15: normally due Nov 2026 ('2026-11').
      final purchaseDate = DateTime(2026, 10, 15);

      // Deferral 2 months -> Jan 2027
      expect(
        calculateInstallmentStartMonth(bpiCard, purchaseDate,
            deferralMonths: 2),
        '2027-01',
      );

      // Deferral 3 months -> Feb 2027
      expect(
        calculateInstallmentStartMonth(bpiCard, purchaseDate,
            deferralMonths: 3),
        '2027-02',
      );
    });

    test('account without billing cycle shifts from purchase month', () {
      final purchaseDate = DateTime(2026, 10, 25);
      expect(
        calculateInstallmentStartMonth(cashAccount, purchaseDate),
        '2026-10',
      );
      expect(
        calculateInstallmentStartMonth(cashAccount, purchaseDate,
            deferralMonths: 2),
        '2026-12',
      );
    });

    test('null account with deferral shifts from purchase month', () {
      final purchaseDate = DateTime(2026, 11, 5);
      expect(
        calculateInstallmentStartMonth(null, purchaseDate, deferralMonths: 1),
        '2026-12',
      );
    });
  });

  group('installmentCycleExplanation', () {
    final card = FinancialAccount(
      id: 'card',
      name: 'Credit Card',
      category: AccountCategory.creditCard,
      balance: 0,
      colorHex: '#000000',
      icon: 'card',
      statementDay: 20,
      paymentDueDay: 15,
    );

    test(
        'returns null for non-billing accounts or null account without deferral',
        () {
      expect(installmentCycleExplanation(null, DateTime(2026, 10, 25)), isNull);

      final noCycle = FinancialAccount(
        id: 'no-cycle',
        name: 'Bank',
        category: AccountCategory.savings,
        balance: 100,
        colorHex: '#000000',
        icon: 'savings',
      );
      expect(
          installmentCycleExplanation(noCycle, DateTime(2026, 10, 25)), isNull);
    });

    test('returns clear explanation when purchase is before statement cut-off',
        () {
      final text = installmentCycleExplanation(card, DateTime(2026, 10, 15));
      expect(text, isNotNull);
      expect(text, contains('Charged on'));
      expect(text, contains('statement'));
      expect(text, contains('Due'));
    });

    test('returns clear explanation when purchase is after statement cut-off',
        () {
      final text = installmentCycleExplanation(card, DateTime(2026, 10, 25));
      expect(text, isNotNull);
      expect(text, contains('cut-off'));
      expect(text, contains('Charged on'));
      expect(text, contains('Due'));
    });

    test('includes deferral information when deferralMonths > 0 on credit card',
        () {
      final text = installmentCycleExplanation(card, DateTime(2026, 10, 25),
          deferralMonths: 2);
      expect(text, isNotNull);
      expect(text, contains('Deferred 2 mos'));
      expect(text, contains('Charged on'));
      expect(text, contains('Due in Feb 2027'));
    });

    test('explains deferred payment on non-billing account', () {
      final text = installmentCycleExplanation(null, DateTime(2026, 10, 25),
          deferralMonths: 2);
      expect(text, isNotNull);
      expect(text, contains('deferred by 2 months'));
      expect(text, contains('Due in Dec 2026'));
    });

    // Closes the 15th, due 15 days later: the Jan 15 statement is due Jan 30.
    final monthEnd = FinancialAccount(
      id: 'month-end',
      name: 'Month-end due',
      category: AccountCategory.creditCard,
      balance: 0,
      colorHex: '#000000',
      icon: 'card',
      statementDay: 15,
      dueDaysAfterStatement: 15,
    );

    test('deferral from a 30th due date does not overflow into a later month',
        () {
      final bought = DateTime(2026, 1, 10);
      for (final n in [1, 2, 3]) {
        final start =
            calculateInstallmentStartMonth(monthEnd, bought, deferralMonths: n);
        final text =
            installmentCycleExplanation(monthEnd, bought, deferralMonths: n)!;
        final expected = DateFormat('MMM yyyy')
            .format(DateTime.parse('$start-01')); // the month that is saved
        expect(text, contains('Due in $expected'), reason: '$n mo deferral');
      }
      // Jan 30 + 1 month used to read "Mar 2026" while 2026-02 was saved.
      expect(installmentCycleExplanation(monthEnd, bought, deferralMonths: 1),
          contains('Due in Feb 2026'));
      expect(
          calculateInstallmentStartMonth(monthEnd, bought, deferralMonths: 1),
          '2026-02');
    });

    test('deferral from a 31st due date (Jan 31 + 1 month) stays in Feb', () {
      // Closes the 16th, due 15 days later → Jan 31.
      final jan31 = FinancialAccount(
        id: 'jan31',
        name: 'Jan 31 due',
        category: AccountCategory.creditCard,
        balance: 0,
        colorHex: '#000000',
        icon: 'card',
        statementDay: 16,
        dueDaysAfterStatement: 15,
      );
      final bought = DateTime(2026, 1, 5);
      expect(jan31.cycleContaining(bought)!.due, DateTime(2026, 1, 31));
      expect(installmentCycleExplanation(jan31, bought, deferralMonths: 1),
          contains('Due in Feb 2026'));
    });

    test('a purchase on the cut-off day is labelled "on", not "before"', () {
      final text = installmentCycleExplanation(card, DateTime(2026, 10, 20))!;
      expect(text, contains('Purchased on the Oct 20 cut-off'));
      expect(text, contains('Charged on Oct 20 statement'));
    });

    test('an unclamped statement day agrees with the clamped cycle math', () {
      // Day 31 is stored but cycles close on the 28th — a purchase on the 29th
      // rides the NEXT statement, so it is "after" the cut-off.
      final legacy = FinancialAccount(
        id: 'legacy',
        name: 'Legacy',
        category: AccountCategory.creditCard,
        balance: 0,
        colorHex: '#000000',
        icon: 'card',
        statementDay: 31,
        paymentDueDay: 10,
      );
      final text = installmentCycleExplanation(legacy, DateTime(2026, 10, 29))!;
      expect(text, contains('Purchased after Oct 28 cut-off'));
      expect(text, contains('Charged on Nov 28 statement'));
    });
  });

  group('Installment.fromJson numeric tolerance', () {
    test('accepts doubles for totalMonths and deferralMonths', () {
      final parsed = Installment.fromJson({
        'id': 'cloud-1',
        'name': 'Phone',
        'accountId': 'card-1',
        'totalAmount': 12000,
        'monthlyAmount': 1000,
        'totalMonths': 12.0,
        'startMonth': '2026-11',
        'deferralMonths': 2.0,
        'interestRate': 1,
      });
      expect(parsed.totalMonths, 12);
      expect(parsed.deferralMonths, 2);
      expect(parsed.interestRate, 1.0);
      expect(parsed.endMonth, '2027-10');
    });
  });
}
