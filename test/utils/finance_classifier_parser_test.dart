import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/finance_classifier_parser.dart';

FinancialAccount _acc(String name, {String? id}) => FinancialAccount(
      id: id ?? name.toLowerCase(),
      name: name,
      category: AccountCategory.bank,
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

PreparseResult _preparse({String raw = '500 gcash food'}) =>
    PreparseResult(rawInput: raw, amount: 500);

void main() {
  final bpi = _acc('BPI');
  final gcash = _acc('GCash');
  final food = _cat('Food', CategoryType.expense);
  final salary = _cat('Salary', CategoryType.income);

  final accounts = [bpi, gcash];
  final categories = [food, salary];

  ClassifierStep? parse(String text) => parseFinanceClassifierResponse(
        text: text,
        accounts: accounts,
        categories: categories,
        preparse: _preparse(),
      );

  group('happy paths', () {
    test('resolved outflow with all required fields', () {
      final step = parse(
          '{"step":"resolved","amount":500,"type":"outflow","account":"GCash",'
          '"category":"Food","learnedToken":"hamburger","confidence":0.9,'
          '"summaryText":"Log ₱500 outflow → Food (GCash)?"}');

      expect(step, isA<StepResolved>());
      final r = step as StepResolved;
      expect(r.transaction.amount, 500);
      expect(r.transaction.type, TransactionType.outflow);
      expect(r.transaction.accountId, gcash.id);
      expect(r.transaction.categoryId, food.id);
      expect(r.learnedToken, 'hamburger');
      expect(r.summaryText, contains('Food'));
    });

    test('resolved transfer with transferTo set', () {
      final step = parse('{"step":"resolved","amount":1000,"type":"transfer",'
          '"account":"BPI","transferTo":"GCash","category":null,'
          '"confidence":0.95,"summaryText":"Transfer ₱1000 BPI → GCash?"}');

      expect(step, isA<StepResolved>());
      final r = step as StepResolved;
      expect(r.transaction.type, TransactionType.transfer);
      expect(r.transaction.accountId, bpi.id);
      expect(r.transaction.transferToAccountId, gcash.id);
      expect(r.transaction.categoryId, isNull);
    });

    test('clarify with quick replies', () {
      final step =
          parse('{"step":"clarify","question":"Did you mean BPI or BDO?",'
              '"quickReplies":[{"label":"BPI","replyText":"BPI"},'
              '{"label":"BDO","replyText":"BDO"}]}');

      expect(step, isA<StepClarify>());
      final c = step as StepClarify;
      expect(c.question, 'Did you mean BPI or BDO?');
      expect(c.quickReplies, hasLength(2));
      expect(c.quickReplies!.first.label, 'BPI');
    });

    test('give_up with reason', () {
      final step = parse('{"step":"give_up","reason":"Too ambiguous"}');
      expect(step, isA<StepGiveUp>());
      expect((step as StepGiveUp).reason, 'Too ambiguous');
    });

    test('tolerates prose around the JSON object', () {
      final step =
          parse('Sure thing. {"step":"give_up","reason":"x"} ← here you go.');
      expect(step, isA<StepGiveUp>());
    });
  });

  group('validation downgrades', () {
    test('hallucinated account → give_up', () {
      final step = parse('{"step":"resolved","amount":500,"type":"outflow",'
          '"account":"Maya","category":"Food","confidence":0.9}');
      expect(step, isA<StepGiveUp>());
    });

    test('hallucinated category → give_up', () {
      final step = parse('{"step":"resolved","amount":500,"type":"outflow",'
          '"account":"GCash","category":"Snacks","confidence":0.9}');
      expect(step, isA<StepGiveUp>());
    });

    test('category type mismatches the sign → give_up', () {
      // Outflow with an income category — Salary is income, not expense.
      final step = parse('{"step":"resolved","amount":500,"type":"outflow",'
          '"account":"GCash","category":"Salary","confidence":0.9}');
      expect(step, isA<StepGiveUp>());
    });

    test('transfer with missing destination → give_up', () {
      final step = parse('{"step":"resolved","amount":1000,"type":"transfer",'
          '"account":"BPI","transferTo":null,"confidence":0.9}');
      expect(step, isA<StepGiveUp>());
    });

    test('transfer with same source and destination → give_up', () {
      final step = parse('{"step":"resolved","amount":1000,"type":"transfer",'
          '"account":"BPI","transferTo":"BPI","confidence":0.9}');
      expect(step, isA<StepGiveUp>());
    });

    test('confidence below floor downgrades resolved to clarify', () {
      final step = parse('{"step":"resolved","amount":500,"type":"outflow",'
          '"account":"GCash","category":"Food","confidence":0.4}');
      expect(step, isA<StepClarify>());
    });

    test('missing amount → give_up', () {
      final step =
          parse('{"step":"resolved","type":"outflow","account":"GCash",'
              '"category":"Food","confidence":0.9}');
      // amount falls through to preparse.amount (500) — should resolve.
      expect(step, isA<StepResolved>());
    });

    test('non-positive amount → give_up', () {
      final step = parse(
          '{"step":"resolved","amount":0,"type":"outflow","account":"GCash",'
          '"category":"Food","confidence":0.9}');
      // Explicit zero is invalid — service should not silently fall back to
      // the preparse amount when the model actively states a bad value.
      expect(step, isA<StepGiveUp>());
    });
  });

  group('malformed input', () {
    test('non-JSON returns null', () {
      expect(parse('no json here'), isNull);
    });

    test('invalid JSON returns null', () {
      expect(parse('{this is not json}'), isNull);
    });

    test('unknown step value returns null', () {
      expect(parse('{"step":"unknown"}'), isNull);
    });

    test('clarify with empty question returns null', () {
      expect(parse('{"step":"clarify","question":""}'), isNull);
    });
  });

  group('quick reply parsing', () {
    test('drops entries with empty label', () {
      final step = parse('{"step":"clarify","question":"Which?",'
          '"quickReplies":[{"label":"","replyText":"x"},'
          '{"label":"OK","replyText":"OK"}]}');
      expect(step, isA<StepClarify>());
      expect((step as StepClarify).quickReplies, hasLength(1));
    });

    test('empty quickReplies array → null replies, not empty list', () {
      final step =
          parse('{"step":"clarify","question":"Which?","quickReplies":[]}');
      expect(step, isA<StepClarify>());
      expect((step as StepClarify).quickReplies, isNull);
    });
  });
}
