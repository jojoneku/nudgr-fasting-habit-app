import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/settle_request.dart';
import 'package:intermittent_fasting/utils/settle_copy.dart';
import 'package:intermittent_fasting/utils/settle_rules.dart';

/// Plan 071 Phase 5: the checks the mobile Settle sheet and the web Settle
/// dialog share.
void main() {
  FinancialAccount account({
    double balance = 1000,
    AccountCategory category = AccountCategory.bank,
  }) =>
      FinancialAccount(
        id: 'a',
        name: 'BPI',
        category: category,
        balance: balance,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );

  group('parseSettleAmount', () {
    test('ignores thousands separators and spaces', () {
      expect(parseSettleAmount(' 1,234.50 '), 1234.5);
    });
    test('is null for text that is not a number', () {
      expect(parseSettleAmount('abc'), isNull);
      expect(parseSettleAmount(''), isNull);
    });
  });

  group('settleAmountError', () {
    test('needs a positive, finite amount for every kind', () {
      for (final kind in SettleKind.values) {
        expect(settleAmountError(amount: null, kind: kind, scheduled: 100),
            'Enter an amount');
        expect(settleAmountError(amount: 0, kind: kind, scheduled: 100),
            'Enter an amount');
        expect(settleAmountError(amount: -5, kind: kind, scheduled: 100),
            'Enter an amount');
        expect(
            settleAmountError(
                amount: double.infinity, kind: kind, scheduled: 100),
            'Enter an amount');
      }
    });

    test('blocks a card payment above what is owed', () {
      expect(
        settleAmountError(
            amount: 2600, kind: SettleKind.cardPayment, scheduled: 2500),
        'More than the ₱2,500.00 owed',
      );
      expect(
        settleAmountError(
            amount: 2500, kind: SettleKind.cardPayment, scheduled: 2500),
        isNull,
      );
    });

    test('a card with nothing owed takes any positive amount', () {
      expect(
        settleAmountError(
            amount: 500, kind: SettleKind.cardPayment, scheduled: 0),
        isNull,
      );
    });

    test('the other kinds allow an overpayment', () {
      for (final kind in [
        SettleKind.bill,
        SettleKind.receivable,
        SettleKind.setAside,
        SettleKind.installment,
      ]) {
        expect(
            settleAmountError(amount: 999, kind: kind, scheduled: 100), isNull);
      }
    });
  });

  group('settleShortBalance', () {
    test('true only when the amount is above the balance', () {
      expect(settleShortBalance(amount: 1500, from: account()), isTrue);
      expect(settleShortBalance(amount: 1000, from: account()), isFalse);
      expect(settleShortBalance(amount: 1000.004, from: account()), isFalse);
    });

    test('a liability is never short', () {
      final card = account(balance: 200, category: AccountCategory.creditCard);
      expect(settleShortBalance(amount: 5000, from: card), isFalse);
    });
  });

  group('settleShortBalanceNote', () {
    test('names the balance and the gap', () {
      expect(
        settleShortBalanceNote(
            kind: SettleKind.bill, amount: 1500, from: account()),
        '₱1,000.00 · short by ₱500.00. BPI does not have enough. Pick '
        'another account, or move money in first.',
      );
    });

    test('is null for a receivable, no account, or enough money', () {
      expect(
          settleShortBalanceNote(
              kind: SettleKind.receivable, amount: 1500, from: account()),
          isNull);
      expect(
          settleShortBalanceNote(
              kind: SettleKind.bill, amount: 1500, from: null),
          isNull);
      expect(
          settleShortBalanceNote(
              kind: SettleKind.bill, amount: 500, from: account()),
          isNull);
    });
  });

  test('only bills and receivables offer the ledger toggle', () {
    expect(
      [for (final k in SettleKind.values) settleOffersLedgerToggle(k)],
      [true, true, false, false, false],
    );
  });

  test('installments never ask for an account; nothing does off-ledger', () {
    expect(settleAsksAccount(SettleKind.installment, recordInLedger: true),
        isFalse);
    expect(settleAsksAccount(SettleKind.bill, recordInLedger: true), isTrue);
    expect(settleAsksAccount(SettleKind.bill, recordInLedger: false), isFalse);
  });

  group('SettleCopy', () {
    const one = [SettleTarget(id: 'b', name: 'Meralco', amount: 500)];
    const two = [
      SettleTarget(id: 'b', name: 'Meralco', amount: 500),
      SettleTarget(id: 'c', name: 'Maynilad', amount: 300),
    ];

    test('single and batch titles and buttons', () {
      const single =
          SettleCopy(kind: SettleKind.bill, targets: one, isBatch: false);
      expect(single.title, 'Mark Meralco paid');
      expect(single.confirmLabel, 'Mark paid');
      const batch =
          SettleCopy(kind: SettleKind.bill, targets: two, isBatch: true);
      expect(batch.title, 'Pay 2 bills');
      expect(batch.confirmLabel, 'Mark 2 paid');
      expect(batch.total, 800);
      expect(batch.subtitle,
          '₱800.00 total · each bill settles for its own amount');
    });

    test('the card payment failure verb', () {
      const copy = SettleCopy(
          kind: SettleKind.cardPayment, targets: one, isBatch: false);
      expect(copy.failureVerb, 'record payment');
      expect(copy.accountLabel, 'Pay from');
    });
  });
}
