import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/advisor_event.dart';
import 'package:intermittent_fasting/models/advisor_reply.dart';

/// Plan 065 phase 5: each advisor reply carries the user's AI usage today.
void main() {
  group('AdvisorUsage.fromJson', () {
    test('reads count, cap and cost', () {
      final usage = AdvisorUsage.fromJson(
          {'count': 7, 'cap': 100, 'cost_usd': 0.008775})!;

      expect(usage.count, 7);
      expect(usage.cap, 100);
      expect(usage.costUsd, closeTo(0.008775, 1e-9));
    });

    test('a tool-loop hop has no count; an unknown model has no cost', () {
      final usage =
          AdvisorUsage.fromJson({'count': null, 'cap': 100, 'cost_usd': null})!;

      expect(usage.count, isNull);
      expect(usage.costUsd, isNull);
    });

    test('a whole-number cost is read as a double', () {
      expect(AdvisorUsage.fromJson({'cap': 100, 'cost_usd': 0})!.costUsd, 0.0);
    });

    test('anything that is not a usage object is null', () {
      expect(AdvisorUsage.fromJson(null), isNull);
      expect(AdvisorUsage.fromJson('7/100'), isNull);
      expect(AdvisorUsage.fromJson({'count': 7}), isNull);
      expect(AdvisorUsage.fromJson({'cap': '100'}), isNull);
    });
  });

  test('the buffered reply body carries it', () {
    final reply = AdvisorReply.fromJson({
      'response': 'Fine.',
      'ai_usage': {'count': 3, 'cap': 100, 'cost_usd': 0.01},
    });

    expect(reply.usage?.count, 3);
    expect(reply.usage?.cap, 100);
  });

  test('the streamed end frame carries it', () {
    final event = AdvisorEvent.fromJson({
      'type': 'end',
      'response': 'Fine.',
      'ai_usage': {'count': 4, 'cap': 100, 'cost_usd': 0.02},
    });

    expect(event.reply?.usage?.count, 4);
    expect(event.reply?.usage?.costUsd, 0.02);
  });

  test('a reply from an older server has no usage', () {
    expect(AdvisorReply.fromJson({'response': 'Fine.'}).usage, isNull);
  });
}
