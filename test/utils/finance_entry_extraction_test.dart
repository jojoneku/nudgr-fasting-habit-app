import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/extracted_entry.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/finance_entry_extraction.dart';

FinancialAccount _acc(String name,
        {String? id, AccountCategory category = AccountCategory.bank}) =>
    FinancialAccount(
      id: id ?? name.toLowerCase(),
      name: name,
      category: category,
      balance: 0,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

FinanceCategory _cat(String name, CategoryType type, {String? id}) =>
    FinanceCategory(
      id: id ?? name.toLowerCase(),
      name: name,
      type: type,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

void main() {
  final maribank = _acc('MariBank');
  final gcash = _acc('GCash');
  final bpiCard = _acc('BPI Credit Card', category: AccountCategory.creditCard);

  final shopping = _cat('Shopping & Personal', CategoryType.expense);
  final foodDrinks = _cat('Food & Drinks', CategoryType.expense);
  final salary = _cat('Salary', CategoryType.income);

  final accounts = [maribank, gcash, bpiCard];
  final categories = [shopping, foodDrinks, salary];

  // A fixed "now" so date assertions never depend on the day the suite runs.
  final now = DateTime(2026, 8, 30, 14, 30);

  ExtractionResult? parse(String text) => parseFinanceExtractionResponse(
        text: text,
        accounts: accounts,
        categories: categories,
        now: now,
      );

  String entry({
    String type = 'outflow',
    Object? amount = 175,
    Object? account = '"MariBank"',
    Object? transferTo = 'null',
    Object? category = '"Shopping & Personal"',
    String description = 'Personal Shopping',
    Object? date = '"2026-08-29"',
    Object? reimbursable = 'false',
    Object? owedBy = 'null',
    Object? confidence = 0.9,
    String missing = '[]',
  }) =>
      '{"type":"$type","amount":$amount,"account":$account,'
      '"transferTo":$transferTo,"category":$category,'
      '"description":"$description","note":null,"date":$date,'
      '"reimbursable":$reimbursable,"expectedReimbursementDate":null,'
      '"owedBy":$owedBy,"confidence":$confidence,"missing":$missing}';

  String wrap(List<String> entries, {String unclear = 'null'}) =>
      '{"entries":[${entries.join(',')}],"unclear":$unclear}';

  group('the regression that motivated this', () {
    // "Can you add in maribank expenses 175 and 90 for personal shopping.
    //  then 115 for food and drinks avocado ice cream all yesterday."
    //
    // The old pipeline split this on "and"/"then", dropped "drinks avocado ice
    // cream all yesterday" for carrying no digit, and classified each fragment
    // in isolation — so only the first entry got the account, none got the
    // date, and the ice cream lost its description. The model now sees the
    // whole sentence, so the shared account and the shared date reach all
    // three rows.
    test('shared account and date apply to every entry', () {
      final result = parse(wrap([
        entry(amount: 175, description: 'Personal Shopping'),
        entry(amount: 90, description: 'Personal Shopping'),
        entry(
          amount: 115,
          category: '"Food & Drinks"',
          description: 'Avocado Ice Cream',
        ),
      ]))!;

      expect(result.entries, hasLength(3));
      expect(
          result.entries.every((e) => e.txn.accountId == maribank.id), isTrue,
          reason: 'the account was named once, for the whole message');
      expect(
        result.entries.every((e) => e.txn.date == DateTime(2026, 8, 29)),
        isTrue,
        reason: '"all yesterday" dates every entry, not just the last',
      );
      expect(result.entries.last.txn.description, 'Avocado Ice Cream');
      expect(result.entries.last.txn.categoryId, foodDrinks.id);
      expect(result.entries.every((e) => e.isReady), isTrue);
    });
  });

  group('binding entities', () {
    test('binds account and category names to real ids', () {
      final e = parse(wrap([entry()]))!.entries.single;
      expect(e.txn.accountId, maribank.id);
      expect(e.txn.categoryId, shopping.id);
      expect(e.txn.amount, 175);
      expect(e.txn.type, TransactionType.outflow);
    });

    test('matches names case-insensitively', () {
      final e = parse(wrap([entry(account: '"maribank"')]))!.entries.single;
      expect(e.txn.accountId, maribank.id);
    });

    test('an invented account marks the field missing, keeping the row', () {
      final e = parse(wrap([entry(account: '"BDO Savings"')]))!.entries.single;

      expect(e.txn.accountId, isNull, reason: 'never a fabricated id');
      expect(e.missing, contains(EntryField.account));
      expect(e.isReady, isFalse);
      // The rest of the row survives — this is the whole point.
      expect(e.txn.amount, 175);
      expect(e.txn.categoryId, shopping.id);
    });

    test('an invented category marks only that field missing', () {
      final e = parse(wrap([entry(category: '"Groceries"')]))!.entries.single;
      expect(e.missing, {EntryField.category});
      expect(e.txn.accountId, maribank.id);
    });

    test('a model-declared missing field is honoured', () {
      final e = parse(wrap([
        entry(account: 'null', missing: '["account"]'),
      ]))!
          .entries
          .single;
      expect(e.missing, contains(EntryField.account));
    });

    test('a gap the model forgot to declare is still caught', () {
      // missing:[] but no account — we verify every field ourselves rather
      // than trusting the declaration, so this cannot look complete.
      final e = parse(wrap([entry(account: 'null')]))!.entries.single;
      expect(e.missing, contains(EntryField.account));
      expect(e.isReady, isFalse);
    });
  });

  group('type and category agreement', () {
    test('the category settles the direction when type is omitted', () {
      final e = parse(wrap([
        entry(type: '', category: '"Salary"', amount: 25000),
      ]))!
          .entries
          .single;
      expect(e.txn.type, TransactionType.inflow);
      expect(e.missing, isEmpty);
    });

    test('a type contradicting its category yields to the category', () {
      final e = parse(wrap([
        entry(type: 'outflow', category: '"Salary"', amount: 25000),
      ]))!
          .entries
          .single;
      expect(e.txn.type, TransactionType.inflow);
    });
  });

  group('transfers', () {
    test('binds a destination account and takes no category', () {
      final e = parse(wrap([
        entry(
          type: 'transfer',
          account: '"GCash"',
          transferTo: '"MariBank"',
          category: 'null',
        ),
      ]))!
          .entries
          .single;

      expect(e.txn.type, TransactionType.transfer);
      expect(e.txn.accountId, gcash.id);
      expect(e.txn.transferToAccountId, maribank.id);
      expect(e.txn.categoryId, isNull);
      expect(e.isReady, isTrue);
    });

    test('a destination equal to the source is treated as absent', () {
      final e = parse(wrap([
        entry(
          type: 'transfer',
          account: '"GCash"',
          transferTo: '"GCash"',
          category: 'null',
        ),
      ]))!
          .entries
          .single;

      expect(e.txn.transferToAccountId, isNull);
      expect(e.missing, contains(EntryField.transferTo));
    });
  });

  group('dates', () {
    test('reads an absolute date', () {
      final e = parse(wrap([entry(date: '"2026-08-29"')]))!.entries.single;
      expect(e.txn.date, DateTime(2026, 8, 29));
    });

    test('a missing date stays null for the commit path to stamp', () {
      final e = parse(wrap([entry(date: 'null')]))!.entries.single;
      expect(e.txn.date, isNull);
    });

    test('a future date is rejected rather than committed', () {
      // Almost always the model mis-resolving a relative phrase.
      final e = parse(wrap([entry(date: '"2027-01-05"')]))!.entries.single;
      expect(e.txn.date, isNull);
    });

    test('today itself is accepted', () {
      final e = parse(wrap([entry(date: '"2026-08-30"')]))!.entries.single;
      expect(e.txn.date, DateTime(2026, 8, 30));
    });

    test('an unparseable date does not kill the row', () {
      final e = parse(wrap([entry(date: '"yesterday"')]))!.entries.single;
      expect(e.txn.date, isNull);
      expect(e.txn.amount, 175);
    });
  });

  group('reimbursable', () {
    test('carries the debtor when flagged', () {
      final e = parse(wrap([
        entry(reimbursable: 'true', owedBy: '"Jana"'),
      ]))!
          .entries
          .single;
      expect(e.txn.reimbursable, isTrue);
      expect(e.txn.owedBy, 'Jana');
    });

    test('never flags an inflow as reimbursable', () {
      final e = parse(wrap([
        entry(
          type: 'inflow',
          category: '"Salary"',
          reimbursable: 'true',
          owedBy: '"Jana"',
        ),
      ]))!
          .entries
          .single;
      expect(e.txn.reimbursable, isFalse);
      expect(e.txn.owedBy, isNull);
    });
  });

  group('confidence', () {
    test('a low-confidence row is flagged but kept', () {
      final e = parse(wrap([entry(confidence: 0.4)]))!.entries.single;
      expect(e.isLowConfidence, isTrue);
      expect(e.txn.amount, 175, reason: 'flagged, never dropped');
    });

    test('a confident row is not flagged', () {
      final e = parse(wrap([entry(confidence: 0.95)]))!.entries.single;
      expect(e.isLowConfidence, isFalse);
    });
  });

  group('malformed and edge cases', () {
    test('non-JSON returns null so the caller can fall back', () {
      expect(parse('I could not read that, sorry.'), isNull);
    });

    test('truncated JSON returns null', () {
      expect(parse('{"entries":[{"type":"outflow","amount":175'), isNull);
    });

    test('prose around the JSON is tolerated', () {
      final result = parse('Here you go:\n${wrap([entry()])}\nHope that helps');
      expect(result?.entries, hasLength(1));
    });

    test('an unclear response with no entries carries the question', () {
      final result = parse('{"entries":[],"unclear":"How much was it?"}')!;
      expect(result.isEmpty, isTrue);
      expect(result.unclear, 'How much was it?');
    });

    test('entries are capped', () {
      final result = parse(wrap([
        for (var i = 0; i < kMaxExtractedEntries + 5; i++)
          entry(amount: 10 + i),
      ]))!;
      expect(result.entries, hasLength(kMaxExtractedEntries));
    });

    test('a row with nothing usable is dropped, not rendered blank', () {
      final result = parse(wrap([
        entry(amount: 'null', account: 'null', category: 'null'),
        entry(),
      ]))!;
      expect(result.entries, hasLength(1));
      expect(result.entries.single.txn.amount, 175);
    });

    test('a zero amount counts as missing', () {
      final e = parse(wrap([entry(amount: 0)]))!.entries.single;
      expect(e.missing, contains(EntryField.amount));
    });
  });

  group('prompt', () {
    String build({String message = 'coffee 120 gcash'}) =>
        buildFinanceExtractionPrompt(
          message: message,
          categories: categories,
          accounts: accounts,
          learnedMappings: {'jollibee': foodDrinks.id},
          now: now,
          categoryNameFor: (id) =>
              categories.where((c) => c.id == id).firstOrNull?.name ?? '',
        );

    test('carries today as an absolute date and a weekday', () {
      final p = build();
      expect(p, contains('TODAY: 2026-08-30'));
      expect(p, contains('Sunday'));
    });

    test('lists the real account and category names', () {
      final p = build();
      expect(p, contains('MariBank'));
      expect(p, contains('Shopping & Personal'));
      expect(p, contains('BPI Credit Card'));
    });

    test('sends the learned dictionary as names, not ids', () {
      final p = build();
      expect(p, contains('"jollibee":"Food & Drinks"'));
      expect(p, isNot(contains('"jollibee":"food & drinks"')));
    });

    test('states the context-inheritance rule the old pipeline could not', () {
      expect(build(), contains('CONTEXT STATED ONCE APPLIES TO EVERY ENTRY'));
    });

    test('puts the message last, after the stable blocks', () {
      final p = build(message: 'coffee 120 gcash');
      expect(p.indexOf('ACCOUNTS'), lessThan(p.indexOf('MESSAGE:')));
      expect(p.indexOf('RULES:'), lessThan(p.indexOf('MESSAGE:')));
    });

    test('escapes quotes in the message', () {
      expect(build(message: 'paid "rent" 5000'), contains("paid 'rent' 5000"));
    });
  });
}
