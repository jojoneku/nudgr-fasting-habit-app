import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/account_badge.dart';

void main() {
  group('accountMonogram — curated brand wordmarks', () {
    const cases = {
      'Metrobank Payroll': 'MB',
      'UnionBank': 'UB',
      'Maribank Savings': 'Mari',
      'GoTyme Bank': 'GT',
      'GCash Main': 'GCash',
      'Maya Personal': 'Maya',
      'Security Bank': 'SB',
    };
    cases.forEach((name, expected) {
      test('"$name" → "$expected"', () {
        expect(accountMonogram(name), expected);
      });
    });
  });

  group('accountMonogram — heuristic fallback', () {
    test('all-caps acronym is kept as-is', () {
      expect(accountMonogram('BPI Personal'), 'BPI');
      expect(accountMonogram('RCBC'), 'RCBC');
    });
    test('two words with no brand match → initials', () {
      expect(accountMonogram('Wells Fargo'), 'WF');
    });
    test('single non-brand word → first two letters', () {
      expect(accountMonogram('Chase'), 'CH');
    });
    test('empty name is handled', () {
      expect(accountMonogram('   '), '?');
    });
  });

  group('resolveAccountBadge', () {
    test('a catalog key resolves to that icon on a solid tile', () {
      final spec = resolveAccountBadge(
        iconKey: 'beach',
        category: AccountCategory.bank,
        name: 'Vacation Fund',
      );
      expect(spec.isMonogram, isFalse);
      expect(spec.icon, kAccountIconCatalog['beach']);
      expect(spec.solid, isTrue);
    });

    test('monogram sentinel forces a monogram even for cash', () {
      final spec = resolveAccountBadge(
        iconKey: kMonogramBadgeKey,
        category: AccountCategory.cash,
        name: 'Metrobank Payroll',
      );
      expect(spec.isMonogram, isTrue);
      expect(spec.monogram, 'MB');
    });

    test('bank/eWallet default to a monogram tile', () {
      final bank = resolveAccountBadge(
        iconKey: AccountCategory.bank.name,
        category: AccountCategory.bank,
        name: 'BPI Personal',
      );
      expect(bank.isMonogram, isTrue);
      expect(bank.monogram, 'BPI');
      expect(bank.solid, isTrue);
    });

    test('other categories default to a tinted category icon', () {
      final cash = resolveAccountBadge(
        iconKey: AccountCategory.cash.name,
        category: AccountCategory.cash,
        name: 'Wallet cash',
      );
      expect(cash.isMonogram, isFalse);
      expect(cash.icon, accountCategoryIcon(AccountCategory.cash));
      expect(cash.solid, isFalse);
    });

    test('an unknown/empty iconKey falls back to the category default', () {
      final spec = resolveAccountBadge(
        iconKey: '',
        category: AccountCategory.savings,
        name: 'Rainy day',
      );
      expect(spec.isMonogram, isFalse);
      expect(spec.icon, accountCategoryIcon(AccountCategory.savings));
    });
  });

  group('accountBadgeForeground — contrast', () {
    test('white on dark colors, dark on light colors', () {
      expect(accountBadgeForeground(const Color(0xFF1B2A44)), Colors.white);
      expect(accountBadgeForeground(const Color(0xFFFFE082)),
          const Color(0xFF15161A));
    });
  });
}
