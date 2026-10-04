import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/utils/credit_cycle.dart';

void main() {
  group('Installment model purchaseDate', () {
    test('serializes and deserializes purchaseDate correctly', () {
      final purchaseDate = DateTime(2026, 10, 25);
      final installment = Installment(
        id: 'inst-101',
        name: 'iPhone 18 Pro',
        accountId: 'bpi-card',
        totalAmount: 72000,
        monthlyAmount: 3000,
        totalMonths: 24,
        startMonth: '2026-12',
        purchaseDate: purchaseDate,
        note: '24 months 0% interest',
      );

      final json = installment.toJson();
      expect(json['purchaseDate'], purchaseDate.toIso8601String());

      final roundTrip = Installment.fromJson(json);
      expect(roundTrip.purchaseDate, purchaseDate);
      expect(roundTrip.name, 'iPhone 18 Pro');
      expect(roundTrip.startMonth, '2026-12');
    });

    test('backward compatibility: legacy JSON without purchaseDate is null',
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
      expect(parsed.name, 'MacBook Pro');
    });

    test('copyWith preserves and updates purchaseDate', () {
      final original = Installment(
        id: 'inst-1',
        name: 'Desk',
        accountId: 'card-1',
        totalAmount: 12000,
        monthlyAmount: 1000,
        totalMonths: 12,
        startMonth: '2026-02',
        purchaseDate: DateTime(2026, 1, 15),
      );

      final updatedDate = DateTime(2026, 1, 28);
      final modified = original.copyWith(purchaseDate: updatedDate);
      expect(modified.purchaseDate, updatedDate);
      expect(modified.id, original.id);

      final preserved = original.copyWith(name: 'Standing Desk');
      expect(preserved.purchaseDate, DateTime(2026, 1, 15));
      expect(preserved.name, 'Standing Desk');
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

    test('account without billing cycle falls back to purchase month', () {
      final purchaseDate = DateTime(2026, 10, 25);
      final startMonth =
          calculateInstallmentStartMonth(cashAccount, purchaseDate);
      expect(startMonth, '2026-10');
    });

    test('null account falls back to purchase month', () {
      final purchaseDate = DateTime(2026, 11, 5);
      final startMonth = calculateInstallmentStartMonth(null, purchaseDate);
      expect(startMonth, '2026-11');
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

    test('returns null for non-billing accounts or null account', () {
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
  });
}
