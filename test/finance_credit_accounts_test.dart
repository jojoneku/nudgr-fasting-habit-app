import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/finance_nlp_parser.dart';

FinancialAccount _card({
  String id = 'cc',
  String name = 'BPI CC',
  double balance = 0,
  double? creditLimit,
  int? statementDay,
  int? paymentDueDay,
  double? financeChargeRate,
  String? creditBrand,
}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: AccountCategory.creditCard,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'creditCard',
      creditLimit: creditLimit,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      financeChargeRate: financeChargeRate,
      creditBrand: creditBrand,
    );

void main() {
  group('FinancialAccount credit fields', () {
    test('credit getters compute payable / available / utilization', () {
      final c = _card(balance: 12000, creditLimit: 50000);
      expect(c.currentPayable, 12000);
      expect(c.availableCredit, 38000);
      expect(c.utilization, closeTo(0.24, 0.0001));
    });

    test('availableCredit/utilization are null without a limit', () {
      final c = _card(balance: 1000);
      expect(c.availableCredit, isNull);
      expect(c.utilization, isNull);
    });

    test('non-liability accounts report zero payable', () {
      final bank = FinancialAccount(
        id: 'b',
        name: 'BPI',
        category: AccountCategory.bank,
        balance: 5000,
        colorHex: '#FFFFFF',
        icon: 'bank',
      );
      expect(bank.currentPayable, 0);
      expect(bank.availableCredit, isNull);
    });

    test('JSON round-trip preserves the new fields', () {
      final c = _card(
        balance: 3000,
        creditLimit: 40000,
        statementDay: 5,
        paymentDueDay: 25,
        financeChargeRate: 0.03,
        creditBrand: 'bpi_rewards',
      );
      final restored = FinancialAccount.fromJson(c.toJson());
      expect(restored.creditLimit, 40000);
      expect(restored.statementDay, 5);
      expect(restored.paymentDueDay, 25);
      expect(restored.financeChargeRate, 0.03);
      expect(restored.creditBrand, 'bpi_rewards');
    });

    test('old JSON without credit keys deserializes with nulls', () {
      final legacy = {
        'id': 'x',
        'name': 'Old',
        'category': 'creditCard',
        'balance': 100.0,
        'colorHex': '#FFFFFF',
        'icon': 'creditCard',
      };
      final a = FinancialAccount.fromJson(legacy);
      expect(a.creditLimit, isNull);
      expect(a.statementDay, isNull);
      expect(a.creditBrand, isNull);
    });
  });

  group('pay-credit chat intent', () {
    final card = _card(id: 'cc', name: 'BPI CC');
    final bpi = FinancialAccount(
      id: 'bpi',
      name: 'BPI',
      category: AccountCategory.bank,
      balance: 0,
      colorHex: '#FFFFFF',
      icon: 'bank',
    );
    final gcash = FinancialAccount(
      id: 'gcash',
      name: 'GCash',
      category: AccountCategory.ewallet,
      balance: 0,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );
    final food = FinanceCategory(
      id: 'food',
      name: 'Food',
      type: CategoryType.expense,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

    PreparseResult run(String input, {List<FinancialAccount>? accounts}) =>
        preparseFinanceInput(
          input: input,
          categories: [food],
          accounts: accounts ?? [card, bpi, gcash],
          learnedDict: const {},
        );

    test('"paid bpi cc 5000 from gcash" → transfer funder→card', () {
      final r = run('paid bpi cc 5000 from gcash');
      expect(r.type, TransactionType.transfer);
      expect(r.transferToAccountId, 'cc'); // the credit account
      expect(r.accountId, 'gcash'); // the funder
      expect(r.amount, 5000);
      expect(r.isFullyResolved, isTrue);
    });

    test('without a funder it is a partial transfer (AI clarifies)', () {
      final r = run('settle bpi cc 1200');
      expect(r.type, TransactionType.transfer);
      expect(r.transferToAccountId, 'cc');
      expect(r.accountId, isNull);
      expect(r.isFullyResolved, isFalse);
    });

    test('a pay phrase with no credit account stays an expense', () {
      // No liability among the accounts → ordinary outflow path, not a transfer.
      final r = run('pay food 20', accounts: [bpi, gcash]);
      expect(r.type, TransactionType.outflow);
      expect(r.categoryId, 'food');
    });
  });
}
