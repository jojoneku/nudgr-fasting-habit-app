import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_conversation.dart';
import 'package:intermittent_fasting/models/advisor_route.dart';
import 'package:intermittent_fasting/utils/advisor_routing.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';

/// The route rule and the schema check behind Haiku routing (Plan 065,
/// phase 5). Only a lookup goes to Haiku; anything unclear goes to Sonnet.
void main() {
  group('routeForFirstMessage', () {
    for (final text in [
      'How much budget do I have left?',
      'What was my GCash balance at the end of June?',
      "What's on my BPI statement from last month?",
      'Which receivables are still open?',
      'How many bills are unpaid?',
      'When does my iPhone installment end?',
    ]) {
      test('a lookup goes to Haiku: "$text"', () {
        expect(
            routeForFirstMessage(text, hasImages: false), AdvisorRoute.haiku);
      });
    }

    for (final text in [
      // Planning words, the quick-log veto list.
      'I want to pay 5000 for the BPI card next month',
      'How should I split my bonus?',
      'What if I skip the gym this month?',
      'How do I get out of debt?',
      // Write intent.
      'Add an internet bill for 1299 due on the 20th',
      'Delete my gym bill',
      'Mark the Meralco bill as paid',
      // Advice rather than a figure.
      'Can I afford a 20k phone?',
      'Why is my Landers expense not counted?',
      'Can you review my August transactions?',
      // Nothing to read.
      '   ',
    ]) {
      test('anything else goes to Sonnet: "$text"', () {
        expect(
            routeForFirstMessage(text, hasImages: false), AdvisorRoute.sonnet);
      });
    }

    test('an image goes to Sonnet, even with a lookup caption', () {
      expect(
        routeForFirstMessage('How much is this bill?', hasImages: true),
        AdvisorRoute.sonnet,
      );
    });
  });

  group('toolInputProblem', () {
    final query = financeToolNamed('queryFinance')!;

    test('a valid input has no problem', () {
      expect(
        toolInputProblem(query, {'metric': 'spend', 'top': 5}),
        isNull,
      );
    });

    test('a missing required key is a problem', () {
      expect(toolInputProblem(query, {'groupBy': 'category'}), isNotNull);
    });

    test('a value outside the enum is a problem', () {
      expect(toolInputProblem(query, {'metric': 'banana'}), isNotNull);
    });

    test('a value of the wrong JSON type is a problem', () {
      expect(toolInputProblem(query, {'metric': 'spend', 'top': 'five'}),
          isNotNull);
    });

    test('an integer may arrive as a whole double', () {
      expect(toolInputProblem(query, {'metric': 'spend', 'top': 5.0}), isNull);
    });
  });

  group('AdvisorConversation.route', () {
    AdvisorConversation convo(AdvisorRoute? route) => AdvisorConversation(
          id: 'c1',
          title: 'Chat',
          createdAt: DateTime(2026, 10, 30),
          updatedAt: DateTime(2026, 10, 30),
          messages: const [],
          route: route,
        );

    test('survives a JSON round trip', () {
      final back =
          AdvisorConversation.fromJson(convo(AdvisorRoute.haiku).toJson());
      expect(back.route, AdvisorRoute.haiku);
    });

    test('a conversation saved before routing has no route', () {
      final json = convo(null).toJson();
      expect(json.containsKey('route'), isFalse);
      expect(AdvisorConversation.fromJson(json).route, isNull);
    });

    test('an unknown stored value reads as no route', () {
      final json = convo(AdvisorRoute.haiku).toJson()..['route'] = 'opus';
      expect(AdvisorConversation.fromJson(json).route, isNull);
    });
  });
}
