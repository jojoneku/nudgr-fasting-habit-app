import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/account_category_label.dart';
import 'package:intermittent_fasting/utils/account_form_rules.dart';

/// Plan 071 Phase 1: mobile and web read one copy of the account labels and
/// form rules. These tests pin each value once, so a change shows up in both
/// apps on purpose, not by drift.
void main() {
  test('every account type has exactly one label', () {
    const expected = {
      AccountCategory.bank: 'Bank',
      AccountCategory.ewallet: 'eWallet',
      AccountCategory.cash: 'Cash',
      AccountCategory.savings: 'Savings',
      AccountCategory.goal: 'Goal',
      AccountCategory.timeDeposit: 'Time Deposit',
      AccountCategory.creditCard: 'Credit Card',
      AccountCategory.creditLine: 'Credit Line',
      AccountCategory.bnpl: 'BNPL',
      AccountCategory.investment: 'Investment',
      AccountCategory.custodian: 'External',
    };
    expect(expected.keys, unorderedEquals(AccountCategory.values));
    for (final entry in expected.entries) {
      expect(entry.key.label, entry.value, reason: entry.key.name);
    }
  });

  test('a pocket can only be savings, a goal or a time deposit', () {
    expect(kSubAccountCategories, [
      AccountCategory.savings,
      AccountCategory.goal,
      AccountCategory.timeDeposit,
    ]);
    expect(kTopLevelAccountCategories,
        isNot(contains(AccountCategory.timeDeposit)));
  });

  test('quick-switch lists leave out credit types', () {
    for (final c in [...kTopLevelSwitchable, ...kSubSwitchable]) {
      expect(
        [
          AccountCategory.creditCard,
          AccountCategory.creditLine,
          AccountCategory.bnpl,
        ],
        isNot(contains(c)),
      );
    }
  });

  test('the swatch list has 8 distinct colors', () {
    expect(kAccountColorOptions, hasLength(8));
    expect(kAccountColorOptions.toSet(), hasLength(8));
  });

  group('positiveAmountValidator', () {
    test('rejects blank, zero, negative and malformed input', () {
      for (final v in [null, '', '0', '-5', '1.2.3', '.']) {
        expect(positiveAmountValidator(v), isNotNull, reason: '$v');
      }
    });
    test('accepts a positive amount, with thousands separators', () {
      expect(positiveAmountValidator('1,500.50'), isNull);
    });
  });

  group('optionalAmountValidator', () {
    test('allows blank and zero', () {
      expect(optionalAmountValidator(''), isNull);
      expect(optionalAmountValidator('0'), isNull);
    });
    test('rejects malformed and negative input', () {
      expect(optionalAmountValidator('.'), 'Enter a valid number');
      expect(optionalAmountValidator('-1'), 'Must be 0 or more');
    });
  });

  test('parseAmount ignores separators and returns null when malformed', () {
    expect(parseAmount('12,000.25'), 12000.25);
    expect(parseAmount(' 7 '), 7);
    expect(parseAmount(''), isNull);
    expect(parseAmount('1.2.3'), isNull);
  });
}
