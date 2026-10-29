import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/planning_intent.dart';

void main() {
  group('hasPlanningIntent', () {
    test('matches each planning word, in any case', () {
      for (final text in [
        'I want to pay',
        'she wants it',
        'wanna buy',
        'my plan is',
        'two plans',
        'planning a trip',
        'SHOULD I',
        'if I pay',
        'How do I',
        'next month',
        'thinking of it',
      ]) {
        expect(hasPlanningIntent(text), isTrue, reason: text);
      }
    });

    test('matches whole words only', () {
      for (final text in [
        'gift 500',
        'nextflix 549',
        'planner 300',
        'showroom 1000',
        'I think I spent 200 on grab',
        'grab 245',
      ]) {
        expect(hasPlanningIntent(text), isFalse, reason: text);
      }
    });
  });
}
