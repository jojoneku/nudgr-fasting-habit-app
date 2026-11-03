import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/capture_settings.dart';
import 'package:intermittent_fasting/models/finance/captured_transaction.dart';
import 'package:intermittent_fasting/models/finance/extracted_entry.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/raw_capture.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/capture_parser.dart';

// Redacted shapes of real PH notifications. Keep these in step with
// lib/utils/capture_templates.dart.
const _gcash = 'com.globe.gcash.android';
const _maya = 'com.paymaya';
const _bpi = 'com.bpi.ng.app';
const _mari = 'ph.seabank.seabank';
const _shopee = 'com.shopee.ph';
const _gmail = 'com.google.android.gm';
const _unknown = 'com.example.bank';

final _posted = DateTime(2026, 11, 2, 13, 45);

RawCapture _raw(String pkg, String text,
        {String title = '', String label = ''}) =>
    RawCapture(
      packageName: pkg,
      appLabel: label,
      postedAt: _posted,
      title: title,
      text: text,
      fingerprint: 'fp-${text.hashCode}',
    );

FinancialAccount _acc(String id, String name,
        {AccountCategory category = AccountCategory.ewallet}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: category,
      balance: 0,
      colorHex: '#000000',
      icon: 'wallet',
    );

FinanceCategory _cat(String id, String name,
        {CategoryType type = CategoryType.expense}) =>
    FinanceCategory(
      id: id,
      name: name,
      type: type,
      icon: 'tag',
      colorHex: '#000000',
    );

void main() {
  final accounts = [
    _acc('gcash', 'GCash'),
    _acc('maya', 'Maya'),
    _acc('bpi', 'BPI Savings', category: AccountCategory.bank),
    _acc('bpicc', 'BPI Credit Card', category: AccountCategory.creditCard),
  ];
  final categories = [
    _cat('food', 'Food'),
    _cat('shopping', 'Shopping'),
    _cat('transport', 'Transport'),
    _cat('salary', 'Salary', type: CategoryType.income),
  ];
  const settings = CaptureSettings(
    enabled: true,
    sources: {_gcash, _maya, _bpi},
    accountBySource: {_gcash: 'gcash', _maya: 'maya', _bpi: 'bpi'},
    accountByLast4: {'1234': 'bpicc'},
  );

  CapturedTransaction? tryParse(String pkg, String text, {String title = ''}) =>
      parseCapture(_raw(pkg, text, title: title),
          settings: settings, accounts: accounts, categories: categories);
  CapturedTransaction parse(String pkg, String text, {String title = ''}) =>
      tryParse(pkg, text, title: title)!;

  group('GCash templates', () {
    test('sent to a person is an outflow with the GCash account', () {
      final c = parse(
        _gcash,
        'You have sent PHP 285.00 to JUAN D. via GCash. Ref. No. 1234567890. '
        'Your new balance is PHP 1,715.00.',
      );
      expect(c.draft.amount, 285.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.accountId, 'gcash');
      expect(c.draft.description, 'JUAN D');
      expect(c.confidence, 1.0);
      expect(c.draft.date, _posted);
    });

    test('received from someone is an inflow', () {
      final c = parse(
        _gcash,
        'You have received PHP 500.00 of GCash from MARIA S. w/ message: '
        'thanks. Your new balance is PHP 2,215.00.',
      );
      expect(c.draft.amount, 500.0);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.description, 'MARIA S');
    });

    test('a comma-grouped amount parses', () {
      final c = parse(_gcash, 'You have paid PHP 1,250.00 to JOLLIBEE via QR.');
      expect(c.draft.amount, 1250.0);
      expect(c.draft.description, 'JOLLIBEE');
    });

    test('cash-in from a named bank becomes a transfer bank → wallet', () {
      final c = parse(
          _gcash, 'Cash-in of PHP 1,000.00 via BPI Savings was successful.');
      expect(c.draft.type, TransactionType.transfer);
      expect(c.draft.accountId, 'bpi');
      expect(c.draft.transferToAccountId, 'gcash');
      expect(c.draft.categoryId, FinanceCategory.transferCategoryId);
      expect(c.isReady, isTrue);
    });
  });

  group('Maya templates', () {
    test('paid to a merchant', () {
      final c = parse(_maya, 'You paid PHP 150.00 to 7-ELEVEN. Ref 998877.');
      expect(c.draft.amount, 150.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.accountId, 'maya');
      expect(c.draft.description, '7-ELEVEN');
    });

    test('sent to another own account is a transfer wallet → wallet', () {
      final c = parse(_maya, 'You sent PHP 300.00 to GCash. Ref 1122.');
      expect(c.draft.type, TransactionType.transfer);
      expect(c.draft.accountId, 'maya');
      expect(c.draft.transferToAccountId, 'gcash');
    });
  });

  group('BPI templates', () {
    test('credit card purchase maps by last 4 digits', () {
      final c = parse(
        _bpi,
        'A purchase of PHP 1,500.00 was made on your BPI Credit Card ending '
        'in 1234 at SHOPEE on 02 Nov 2026.',
      );
      expect(c.draft.amount, 1500.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.accountId, 'bpicc');
      expect(c.accountLast4, '1234');
      expect(c.draft.description, 'SHOPEE');
    });

    test('debit with an unmapped last 4 falls back to the source default', () {
      final c = parse(
        _bpi,
        'PHP 5,000.00 was debited from your account ending in 5678 on '
        '02 Nov 2026.',
      );
      expect(c.draft.amount, 5000.0);
      expect(c.draft.accountId, 'bpi');
      expect(c.accountLast4, '5678');
    });

    test('incoming to the account is an inflow', () {
      final c = parse(
        _bpi,
        'You have received PHP 10,000.00 in your BPI account ending in 5678 '
        'from ACME CORP.',
      );
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.amount, 10000.0);
      expect(c.draft.description, 'ACME CORP');
    });
  });

  group('generic pass (no template for the app)', () {
    test('finds amount, direction and counterparty from cue words', () {
      final c = parse(
        _unknown,
        'Your account has been debited ₱420.50 for payment to GRAB. '
        'Available balance: ₱9,579.50.',
      );
      expect(c.draft.amount, 420.5);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.description, 'GRAB');
      expect(c.confidence, 0.6);
      // No account mapping for an unknown source → the chip asks.
      expect(c.draft.accountId, isNull);
      expect(c.missing, contains(EntryField.account));
    });

    test('skips the balance amount when it comes first', () {
      final c = parse(
        _unknown,
        'Balance: P 9,000.00. You received P 2,000.00 from PAYROLL.',
      );
      expect(c.draft.amount, 2000.0);
      expect(c.draft.type, TransactionType.inflow);
    });

    test('an amount with no direction is low confidence and not ready', () {
      final c = parse(_unknown, 'Transaction alert: PHP 99.00. Ref 55.');
      expect(c.draft.amount, 99.0);
      expect(c.draft.type, isNull);
      expect(c.confidence, 0.3);
      expect(c.isReady, isFalse);
      expect(c.missing, contains(EntryField.type));
    });

    test('a number the parser cannot read still yields a row to fill', () {
      final c = parse(
          _unknown, 'Hello! Here is an update on your account ending 1234.',
          title: 'Update');
      expect(c.draft.amount, isNull);
      expect(c.confidence, 0);
      expect(c.missing, contains(EntryField.amount));
      expect(c.draft.description, 'Update');
    });

    test('a text with no digit at all and no template is not a row', () {
      expect(
          tryParse(_unknown, 'Hello! Here is an update on your account.',
              title: 'Update'),
          isNull);
    });

    test('a digit alone does not make a row: no amount, cue or own suffix',
        () {
      // An order number is a digit, not money (Shopee, seen 2026-11-03).
      expect(
          tryParse(_shopee, 'Your order 2411031234 has been shipped.',
              title: 'Shopee'),
          isNull);
      // A direction cue still carries a no-amount row for the user to fill.
      expect(
          tryParse(_unknown, 'Payment received from PAYROLL.', title: 'Alert'),
          isNotNull);
    });

    test('the account named like the source app fills the gap', () {
      const bare = CaptureSettings(enabled: true, sources: {_maya, _shopee});
      CapturedTransaction? p(String pkg, String label, String text) =>
          parseCapture(_raw(pkg, text, label: label),
              settings: bare,
              accounts: [...accounts, _acc('spay', 'ShopeePay')],
              categories: categories);
      // "Maya" the app → the Maya account, with no mapping in settings.
      expect(
          p(_maya, 'Maya', 'You paid PHP 80.00 to STORE.')!.draft.accountId,
          'maya');
      // "Shopee" the app → ShopeePay, by prefix.
      expect(
          p(_shopee, 'Shopee', 'You paid ₱250.00 to SELLER via ShopeePay.')!
              .draft
              .accountId,
          'spay');
      // Mail never guesses from the app name.
      expect(
          p(_gmail, 'Gmail', 'Incoming Interbank Funds Transfer')!
              .draft
              .accountId,
          isNull);
    });

    test('BPI app push masks to three digits (seen on device 2026-11-03)',
        () {
      const s = CaptureSettings(
        enabled: true,
        sources: {_bpi},
        accountBySource: {_bpi: 'bpi'},
        // The BPI email taught the four-digit form of the same account.
        accountByLast4: {'1637': 'bpicc'},
      );
      final c = parseCapture(
          _raw(_bpi, 'Your account XXXXXXX637 has been credited Php 8,500.00.',
              title: 'BPI', label: 'BPI'),
          settings: s,
          accounts: accounts,
          categories: categories)!;
      expect(c.draft.amount, 8500.0);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.accountLast4, '637');
      expect(c.confidence, 1.0);
      // The suffix map matches by trailing digits.
      expect(c.draft.accountId, 'bpicc');
    });

    test('a suffix that fits two learned entries is no guess', () {
      expect(accountForSuffix({'1637': 'a', '2637': 'b'}, '637'), isNull);
      expect(accountForSuffix({'1637': 'a', '2637': 'a'}, '637'), 'a');
      expect(accountForSuffix({'637': 'a'}, '1637'), 'a');
      expect(accountForSuffix({'1234': 'a'}, '637'), isNull);
    });

    test('the user\'s own per-source mapping wins over the name match', () {
      const mapped = CaptureSettings(
        enabled: true,
        sources: {_maya},
        accountBySource: {_maya: 'gcash'},
      );
      final c = parseCapture(
          _raw(_maya, 'You paid PHP 80.00 to STORE.', label: 'Maya'),
          settings: mapped,
          accounts: accounts,
          categories: categories)!;
      expect(c.draft.accountId, 'gcash');
    });
  });

  group('reject-first filter (no row at all)', () {
    test('an OTP or security prompt', () {
      expect(tryParse(_gcash, 'Your GCash OTP is 123456. Do not share it.'),
          isNull);
      expect(
          tryParse(_maya,
              'Use 123456 as your one-time password. Never share your code.'),
          isNull);
    });

    test('a promo, a product nudge or a bill reminder', () {
      expect(tryParse(_gcash, 'Win up to PHP 1,000.00 in vouchers!'), isNull);
      expect(
          tryParse(_gcash,
              'Get ₱50 cashback when you pay with GCash this weekend! Tap to learn more.'),
          isNull);
      expect(
          tryParse(_gcash, 'Your GCredit bill of PHP 300.00 is due.'), isNull);
    });

    test('the Maya refill nudge (seen on device 2026-11-02)', () {
      expect(
          tryParse(
              _maya,
              "Turn on Auto Cash in now or transfer funds from Maya Easy Credit "
              "so you're always ready to pay with Maya without worry. Tap to start.",
              title: 'Your wallet needs a refill'),
          isNull);
      // The body alone, with the title cue gone, still falls to the no-digit
      // floor rather than becoming an amount-less inflow row.
      expect(
          tryParse(
              _maya,
              "Transfer funds from Maya Easy Credit so you're always ready "
              "to pay with Maya.",
              title: 'Maya'),
          isNull);
    });

    test('marketing pushes seen on device 2026-11-03', () {
      expect(tryParse(_shopee, 'Over 50% OFF!', title: 'Shopee'), isNull);
      expect(tryParse(_shopee, '70% OFF holiday deals', title: 'Shopee'),
          isNull);
      expect(
          tryParse(_shopee, 'see order details and track your parcel',
              title: 'Shopee'),
          isNull);
      expect(
          tryParse(_shopee,
              'unlock your Lucky Draw before it expires in 2 hours',
              title: 'Shopee'),
          isNull);
      expect(
          tryParse(_mari,
              'Get a ₱70.00 prepaid Wi-Fi plan so you never run out of data.',
              title: "Don't let your Wi-Fi drop!"),
          isNull);
      expect(
          tryParse(_maya, 'Earn up to ₱4,000.00 when you invite a friend.',
              title: 'earn up'),
          isNull);
    });

    test('a failed, pending or reversed transaction', () {
      expect(
          tryParse(_gcash,
              'Your transfer of PHP 1,250.00 is pending. We will notify you once completed.'),
          isNull);
      expect(tryParse(_maya, 'Payment failed PHP 150.50'), isNull);
    });

    test('a plain cash-back credit is still money in', () {
      final c =
          parse(_gcash, 'You have received PHP 5.00 cashback from JOLLIBEE.');
      expect(c.draft.amount, 5.0);
      expect(c.draft.type, TransactionType.inflow);
    });
  });

  // Redacted real pushes collected from public parser fixtures (see the
  // provenance note in lib/utils/capture_templates.dart).
  group('corpus: GCash real shapes', () {
    test('current push: masked name and phone', () {
      final c = parse(_gcash,
          'You have received PHP 1,096.10 of GCash from MI*A P. 0915••••847.',
          title: 'You have received money in GCash!');
      expect(c.draft.amount, 1096.10);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.description, 'MI*A P');
      expect(c.accountLast4, isNull);
      expect(c.confidence, 1.0);
    });

    test('express send with +63 phone and balance', () {
      final c = parse(
          _gcash,
          'You have received PHP 1000.00 from DO**A RO**F B. +639752505196 w/ MSG: . '
          'Your new balance is PHP 2102.95. Ref. No. 9044057598177.',
          title: 'Express Send Notification');
      expect(c.draft.amount, 1000.0);
      expect(c.draft.description, 'DO**A RO**F B');
    });

    test('the sender phone in brackets is not the user card', () {
      final c = parse(
          _gcash,
          'You have received PHP 500.00 of GCash from MA•IA S. (0917•••5678). '
          'Your new balance is PHP 12,340.50. Ref. No. 1234567890123.');
      expect(c.draft.amount, 500.0);
      expect(c.accountLast4, isNull);
      expect(c.draft.accountId, 'gcash');
      expect(c.draft.description, 'MA•IA S');
    });

    test('InstaPay from an own bank is a transfer bank → wallet', () {
      final c = parse(
          _gcash,
          'You have received PHP 5,000.00 via InstaPay from BPI Savings on Sep 8, 2025 '
          '1:45 PM. Ref. No. 7031245896012.');
      expect(c.draft.type, TransactionType.transfer);
      expect(c.draft.accountId, 'bpi');
      expect(c.draft.transferToAccountId, 'gcash');
      expect(c.confidence, 1.0);
    });

    test('"has been credited to your GCash account"', () {
      final c = parse(
          _gcash,
          'PHP 150.00 has been credited to your GCash account via InstaPay from '
          'SEABANK. Reference No. 104116');
      expect(c.draft.amount, 150.0);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.description, 'SEABANK');
      expect(c.confidence, 1.0);
    });

    test('PESONet credit with no counterparty keeps the title', () {
      final c = parse(
          _gcash,
          'Fund transfer received: your GCash was credited with PHP 1,250.00 via '
          'PESONet. Transaction No. AB1234567890',
          title: 'GCash');
      expect(c.draft.amount, 1250.0);
      expect(c.draft.type, TransactionType.inflow);
    });

    test('an amount with no currency mark right after "received"', () {
      final c = parse(
          _gcash,
          'You have received 1000.00 of GCash from BDO with account ending in 1234. '
          'Your new balance is 5000.00 10-12-2026 09:41 AM. Ref. No. ABC123.',
          title: 'You have received money in GCash!');
      expect(c.draft.amount, 1000.0);
      expect(c.draft.description, 'BDO');
      // "account ending in 1234" is the sender's account, not a card of ours.
      expect(c.accountLast4, isNull);
      expect(c.draft.accountId, 'gcash');
    });

    test('sent with a phone number and a reference', () {
      final c = parse(_gcash,
          'You have sent PHP 500.00 to JUAN D. 09171234567. Ref. No. 123456789.');
      expect(c.draft.amount, 500.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.description, 'JUAN D');
    });

    test('cash out is money out', () {
      final c = parse(_gcash, 'Cash out of PHP 200.00 successful.');
      expect(c.draft.amount, 200.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.confidence, 1.0);
    });
  });

  group('corpus: Maya, GoTyme, MariBank real shapes', () {
    const gotyme = 'ph.com.gotyme';
    const mari = 'ph.seabank.seabank';
    final more = [
      ...accounts,
      _acc('gotyme', 'GoTyme', category: AccountCategory.bank),
      _acc('mari', 'MariBank', category: AccountCategory.bank),
    ];
    const s = CaptureSettings(
      enabled: true,
      sources: {_maya, gotyme, mari},
      accountBySource: {_maya: 'maya', gotyme: 'gotyme', mari: 'mari'},
      accountByLast4: {'1234': 'bpicc'},
    );
    CapturedTransaction p(String pkg, String title, String text) =>
        parseCapture(_raw(pkg, text, title: title),
            settings: s, accounts: more, categories: categories)!;

    test('MariBank incoming transfer from a peer at the same bank '
        '(seen on device 2026-11-03)', () {
      final c = p(mari, 'Successful Incoming Transfer',
          "You've received PHP 40.00 from MariBank with account ending 6357.");
      expect(c.draft.amount, 40.0);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.accountId, 'mari');
      expect(c.draft.description, 'MariBank');
      expect(c.confidence, 1.0);
    });

    test('Maya "You received 500.00 in your wallet via InstaPay"', () {
      final c = p(_maya, 'Money received ↙️',
          'You received 500.00 in your wallet via InstaPay');
      expect(c.draft.amount, 500.0);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.accountId, 'maya');
      expect(c.confidence, 1.0);
    });

    test('Maya with a peso sign', () {
      final c = p(_maya, 'Money received ↙️',
          'You received ₱1,899.00 in your wallet via InstaPay');
      expect(c.draft.amount, 1899.0);
    });

    test('Maya card payment: "your Maya card" is not a transfer to Maya', () {
      final c = p(
          _maya,
          'Maya',
          'You paid PHP 350.00 to Grab Philippines using your Maya card ending in '
              '1234 on Sep 20. Ref: 987654.');
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.description, 'Grab Philippines');
      expect(c.accountLast4, '1234');
      expect(c.draft.transferToAccountId, isNull);
    });

    test('GoTyme keeps an initial in the sender name', () {
      final c = p(gotyme, 'Transfer received',
          'You received P1,250.00 from A. Santos. Your available balance is P9,000.00.');
      expect(c.draft.amount, 1250.0);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.description, 'A. Santos');
      expect(c.draft.accountId, 'gotyme');
      expect(c.confidence, 1.0);
    });

    test('GoTyme sent to an own bank (real): peer suffix ignored, transfer',
        () {
      final c = p(
          gotyme,
          'Transfer successful',
          'You sent P4000.00 to Juan D. Bank Of The Philippine Islands (BPI) '
              '••••••1637.');
      expect(c.draft.amount, 4000.0);
      expect(c.draft.type, TransactionType.transfer);
      expect(c.draft.accountId, 'gotyme');
      expect(c.draft.transferToAccountId, 'bpi');
      expect(c.accountLast4, isNull);
      expect(c.confidence, 1.0);
    });

    test('GoTyme sent to a person is money out', () {
      final c = p(gotyme, 'Transfer successful',
          'You sent P250.00 to Maria Clara GCash ••••••4567.');
      expect(c.draft.type, TransactionType.transfer);
      expect(c.draft.transferToAccountId, 'gcash');
    });

    test('GoTyme GoalSave pocket to deposit (real): money in, own suffix', () {
      final c = p(
          gotyme,
          'GoalSave: Funds transferred',
          "You've transferred P3,500.00 from GoalSave Tuition Fund to your "
              'Deposit account...6634. 02 Nov 20:42.');
      expect(c.draft.amount, 3500.0);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.description, 'GoalSave Tuition Fund');
      expect(c.accountLast4, '6634');
      expect(c.draft.accountId, 'gotyme');
      expect(c.confidence, 1.0);
    });

    test('MariBank incoming: the sender suffix is not our card', () {
      final c = p(mari, 'Successful Incoming Transfer',
          "You've received PHP 780.50 from bank with account ending 1234");
      expect(c.draft.amount, 780.5);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.accountLast4, isNull);
      expect(c.draft.accountId, 'mari');
      expect(c.draft.description, 'Successful Incoming Transfer');
    });

    test('MariBank outgoing, curly apostrophe', () {
      final c = p(mari, 'Transfer Successful',
          'You’ve successfully sent PHP 500.00 to account ending 9012');
      expect(c.draft.amount, 500.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.accountLast4, isNull);
    });

    test('MariBank InstaPay out and debited', () {
      expect(
          p(mari, 'MariBank',
                  'Your InstaPay transfer of PHP 150.00 to 09541230072 was successful. Ref No. 104116')
              .draft
              .type,
          TransactionType.outflow);
      final d = p(mari, 'MariBank',
          'PHP 150.00 has been debited from your account via InstaPay. Ref No. 104116');
      expect(d.draft.type, TransactionType.outflow);
      expect(d.draft.amount, 150.0);
    });
  });

  group('corpus: Google Wallet (payment line + merchant, either order)', () {
    const wallet = 'com.google.android.apps.walletnfcrel';
    const s = CaptureSettings(
      enabled: true,
      sources: {wallet},
      accountByLast4: {'1234': 'bpicc'},
    );
    CapturedTransaction? w(String title, String text) =>
        parseCapture(_raw(wallet, text, title: title),
            settings: s, accounts: accounts, categories: categories);

    test('a debit card label lands on the bank account, not the credit card',
        () {
      // Seen on device 2026-11-03.
      final c = w('STARBUCKS 685 CPG',
          '₱450.00 with BPI Debit Mastercard ••6161')!;
      expect(c.draft.amount, 450.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.description, 'STARBUCKS 685 CPG');
      expect(c.accountLast4, '6161');
      expect(c.draft.accountId, 'bpi');
      expect(c.confidence, 1.0);
    });

    test('PH shape: amount in the text, merchant in the title', () {
      final c = w('STARBUCKS', '₱150.00 with Visa •••• 1234')!;
      expect(c.draft.amount, 150.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.description, 'STARBUCKS');
      expect(c.accountLast4, '1234');
      expect(c.draft.accountId, 'bpicc');
      expect(c.confidence, 1.0);
    });

    test('amount in the title, merchant in the text', () {
      final c = w(r'$4.50 with Visa •••• 1234', 'STARBUCKS')!;
      expect(c.draft.amount, 4.5);
      expect(c.draft.description, 'STARBUCKS');
      expect(c.accountLast4, '1234');
    });

    test('real UA push: ISO code glued to the amount, two-dot mask', () {
      final c = w('SILPO', 'UAH198.00 with Visa PrivatBank ••6810')!;
      expect(c.draft.amount, 198.0);
      expect(c.draft.description, 'SILPO');
      expect(c.accountLast4, '6810');
    });

    test('decimal comma and a middle-dot connector', () {
      final c = w("McDonald's", '12,34 € · Mastercard •• 4321')!;
      expect(c.draft.amount, 12.34);
      expect(c.draft.description, "McDonald's");
      expect(c.accountLast4, '4321');
    });

    test('card label names an own account without a learned suffix', () {
      final c =
          w('SM SUPERMARKET', 'PHP 1,250.00 with BPI Credit Card •••• 9999')!;
      expect(c.draft.amount, 1250.0);
      expect(c.draft.accountId, 'bpicc');
      // The card is the source side, never a transfer to BPI.
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.transferToAccountId, isNull);
    });

    test('merchant embedded in the payment line', () {
      final c = w(r'$5.00 at Starbucks with Visa •••• 1234', '')!;
      expect(c.draft.amount, 5.0);
      expect(c.draft.description, 'Starbucks');
    });

    test('the app name is not a merchant', () {
      final c = w('Google Wallet', r'$3.00 with Visa •••• 1234')!;
      expect(c.draft.amount, 3.0);
      expect(c.draft.description, 'Google Wallet');
      expect(c.draft.categoryId, isNull);
    });

    test('a merchant with digits still yields the payment amount', () {
      final c = w('WOG 555', '75.00 UAH with Visa •••• 3333')!;
      expect(c.draft.amount, 75.0);
      expect(c.draft.description, 'WOG 555');
    });

    test('no payment line means no row at all', () {
      expect(w('Google Wallet', 'Card was added to your device'), isNull);
      expect(w('Visa •••• 1234', 'Contactless setup complete'), isNull);
    });
  });

  group('corpus: Gmail, BPI emails (title = sender, text = email head)', () {
    const gmail = 'com.google.android.gm';
    final more = [
      ...accounts,
      _acc('gotyme', 'GoTyme', category: AccountCategory.bank),
    ];
    const s = CaptureSettings(
      enabled: true,
      sources: {gmail},
      accountBySource: {gmail: 'bpi'},
      senderFilters: {
        gmail: ['BPI']
      },
    );
    CapturedTransaction? g(String title, String text) =>
        parseCapture(_raw(gmail, text, title: title, label: 'Gmail'),
            settings: s, accounts: more, categories: categories);

    test(
        'real head with the amount below the fold: direction, label, no amount',
        () {
      final c = g(
          'BPI InstaPay',
          'Incoming Interbank Funds Transfer Confirmation Dear ELJON, You have '
              'an incoming interbank funds transfer sent via Instapay with the '
              'following details. Interbank Funds Transfer Transaction Details '
              'Reference Number 20261102GOTYPHM2XXXB011244220000006 Transaction '
              'Date and Time Monday, Nov 02 2026; 08:44:27 PM(GMT + 8) Transfer '
              'From…')!;
      expect(c.sourceLabel, 'BPI InstaPay');
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.amount, isNull);
      expect(c.draft.accountId, 'bpi');
      expect(c.draft.description,
          'Incoming Interbank Funds Transfer Confirmation');
      expect(c.missing, contains(EntryField.amount));
    });

    // The whole email as seen on device 2026-11-03 (the BPI side of a
    // GoTyme → BPI InstaPay transfer; 6634 is the GoTyme deposit, 1637 BPI).
    const whole =
        'Incoming Interbank Funds Transfer Confirmation Dear ELJON, You have '
        'an incoming interbank funds transfer sent via Instapay with the '
        'following details. Interbank Funds Transfer Transaction Details '
        'Reference Number 20261102GOTYPHM2XXXB011244220000006 Transaction '
        'Date and Time Monday, Nov 02 2026; 08:44:27 PM(GMT + 8) Transfer '
        'From XXXXXXXX6634 Transfer To XXXXXX1637 Bank Name GoTyme Bank '
        'Transfer Amount PHP 4,000.00 Transfer Service INSTAPAY Important '
        'Reminders: Successful transactions will be credited real-time.';

    test('the whole body (real): own suffix, bank, amount → transfer', () {
      final c = g('BPI InstaPay', whole)!;
      expect(c.draft.amount, 4000.0);
      expect(c.accountLast4, '1637');
      expect(c.draft.type, TransactionType.transfer);
      expect(c.draft.accountId, 'gotyme');
      expect(c.draft.transferToAccountId, 'bpi');
      expect(c.draft.description, 'GoTyme Bank');
      expect(c.confidence, 1.0);
    });

    test('cut off after the bank name: a transfer that needs its amount', () {
      final c = g('BPI InstaPay',
          whole.substring(0, whole.indexOf(' Transfer Amount')))!;
      expect(c.draft.amount, isNull);
      expect(c.draft.type, TransactionType.transfer);
      expect(c.draft.accountId, 'gotyme');
      expect(c.draft.transferToAccountId, 'bpi');
      expect(c.draft.description, 'GoTyme Bank');
      expect(c.missing, contains(EntryField.amount));
    });

    test('cut off after the masked numbers: a mask is never the name', () {
      final c =
          g('BPI InstaPay', whole.substring(0, whole.indexOf(' Bank Name')))!;
      expect(c.draft.amount, isNull);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.draft.accountId, 'bpi');
      expect(c.draft.description,
          'Incoming Interbank Funds Transfer Confirmation');
    });

    test('a half-cut amount is not read as a smaller one', () {
      final c = g('BPI InstaPay',
          '${whole.substring(0, whole.indexOf('4,000.00'))}4,0…')!;
      expect(c.draft.amount, isNull);
    });

    test('a reference number is never read as the amount', () {
      final c = g(
          'BPI InstaPay',
          'Incoming Interbank Funds Transfer Confirmation Reference Number '
              '20261102GOTYPHM2XXXB011244220000006 Transaction Date and Time '
              'Monday, Nov 02 2026; 08:44:27 PM')!;
      expect(c.draft.amount, isNull);
    });
  });

  group('corpus: BPI, VYBE, UnionBank shapes', () {
    const vybe = 'com.indivara.bpi';
    const ub = 'com.unionbankph.online';
    final more = [
      ...accounts,
      _acc('vybe', 'VYBE'),
      _acc('ubcc', 'UnionBank Credit Card',
          category: AccountCategory.creditCard),
      _acc('bdo', 'BDO', category: AccountCategory.bank),
    ];
    const s = CaptureSettings(
      enabled: true,
      sources: {_bpi, vybe, ub},
      accountBySource: {_bpi: 'bpi', vybe: 'vybe', ub: 'ubcc'},
      accountByLast4: {'1234': 'ubcc', '5678': 'bpi'},
    );
    CapturedTransaction p(String pkg, String title, String text) =>
        parseCapture(_raw(pkg, text, title: title),
            settings: s, accounts: more, categories: categories)!;

    test('BPI "Your account XXXX5678 has been credited Php 1,234.00."', () {
      final c = p(
          _bpi, 'BPI', 'Your account XXXX5678 has been credited Php 1,234.00.');
      expect(c.draft.amount, 1234.0);
      expect(c.draft.type, TransactionType.inflow);
      expect(c.accountLast4, '5678');
      expect(c.draft.accountId, 'bpi');
      expect(c.confidence, 1.0);
    });

    test('VYBE transfer to an own bank: peer suffix ignored, transfer kept',
        () {
      final c = p(
          vybe,
          'Bank Transfer Successful',
          'You have transferred Php 1,500.00 to BDO account ending in XXXX5678. '
              'Your new balance is Php 2,000.00. Ref. No. ABC123');
      expect(c.draft.amount, 1500.0);
      expect(c.draft.type, TransactionType.transfer);
      expect(c.draft.accountId, 'vybe');
      expect(c.draft.transferToAccountId, 'bdo');
      expect(c.accountLast4, isNull);
    });

    test('VYBE pay merchant: name before the amount', () {
      final c = p(vybe, 'Pay Merchant',
          'Hi JUAN, your payment to JOLLIBEE of PHP 250.00 has been successfully posted Ref.no. 12345.');
      expect(c.draft.amount, 250.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.description, 'JOLLIBEE');
    });

    test('VYBE top up from an own bank is a transfer', () {
      final c = p(
          vybe,
          'Top Up',
          'You have received Php 1,000.00 from BPI Savings on 10/12/2026 09:41 AM. '
              'Your new wallet balance is Php 1,500.00. Ref. no. 123.');
      expect(c.draft.type, TransactionType.transfer);
      expect(c.draft.accountId, 'bpi');
      expect(c.draft.transferToAccountId, 'vybe');
    });

    test('UnionBank PayDirect: own card suffix, no transfer', () {
      final c = p(
          ub,
          'UnionBank',
          'You paid P1,234.00 to GRAB using your UnionBank Credit Card ending in 1234. '
              'Reference No.: ABC. Thank you for using UnionBank PayDirect!');
      expect(c.draft.amount, 1234.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.description, 'GRAB');
      expect(c.accountLast4, '1234');
      expect(c.draft.accountId, 'ubcc');
      expect(c.draft.transferToAccountId, isNull);
    });

    test('UnionBank "Thank you for using your card for the amount of"', () {
      final c = p(
          ub,
          'UnionBank',
          'Thank you for using your UnionBank Credit Card ending in 1234 for the '
              'amount of PHP 850.00 at STARBUCKS BGC.');
      expect(c.draft.amount, 850.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.description, 'STARBUCKS BGC');
      expect(c.draft.transferToAccountId, isNull);
    });

    test('generic: "card … was used at" is money out', () {
      final c = p(
          'ph.com.bdo.retail',
          'BDO',
          'YOUR CARD ENDING IN 1234 WAS USED AT GRAB ON 01/01 AT 10:00 IN THE '
              'AMOUNT OF PHP1,234.00.');
      expect(c.draft.amount, 1234.0);
      expect(c.draft.type, TransactionType.outflow);
      expect(c.draft.description, 'GRAB');
    });
  });

  group('category resolution', () {
    test('a merchant word that names a category resolves it', () {
      final c = parse(_maya, 'You paid PHP 80.00 to FOOD PANDA.');
      expect(c.draft.categoryId, 'food');
      expect(c.isReady, isTrue);
    });

    test('an income cue only looks at income categories', () {
      final c = parse(_unknown, 'You received PHP 20,000.00 from SALARY DEPT.');
      expect(c.draft.categoryId, 'salary');
    });
  });

  group('row identity', () {
    test('id derives from post time and fingerprint, json round-trips', () {
      final c = parse(_maya, 'You paid PHP 80.00 to FOOD PANDA.');
      expect(c.id, startsWith('cap_${_posted.millisecondsSinceEpoch}_'));
      final back = CapturedTransaction.fromJson(c.toJson());
      expect(back.id, c.id);
      expect(back.draft.amount, 80.0);
      expect(back.draft.categoryId, 'food');
      expect(back.draft.date, _posted);
      expect(back.status, CaptureStatus.pending);
      expect(back.fingerprint, c.fingerprint);
    });
  });
}
