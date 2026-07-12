import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/hub_coach.dart';

void main() {
  group('resolveHubCoachMood', () {
    test('neutral by default', () {
      expect(
        resolveHubCoachMood(
            overGoal: false, billImminent: false, goalsMet: false),
        HubCoachMood.neutral,
      );
    });

    test('over goal is urgent', () {
      expect(
        resolveHubCoachMood(
            overGoal: true, billImminent: false, goalsMet: false),
        HubCoachMood.urgent,
      );
    });

    test('imminent bill is urgent', () {
      expect(
        resolveHubCoachMood(
            overGoal: false, billImminent: true, goalsMet: false),
        HubCoachMood.urgent,
      );
    });

    test('goals met is positive', () {
      expect(
        resolveHubCoachMood(
            overGoal: false, billImminent: false, goalsMet: true),
        HubCoachMood.positive,
      );
    });

    test('urgent wins over positive', () {
      expect(
        resolveHubCoachMood(
            overGoal: true, billImminent: false, goalsMet: true),
        HubCoachMood.urgent,
      );
    });
  });
}
