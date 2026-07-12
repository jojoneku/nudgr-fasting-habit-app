import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/hub_ring_data.dart';

void main() {
  group('HubRings.fast', () {
    test('idle when not fasting', () {
      final d = HubRings.fast(
          isFasting: false,
          elapsedSeconds: 0,
          targetSeconds: 57600,
          isOvertime: false);
      expect(d.state, HubRingState.idle);
      expect(d.value, 0);
      expect(d.caption, 'Fast');
    });

    test('active shows countdown + progress', () {
      // 8h elapsed of a 16h (57600s) goal.
      final d = HubRings.fast(
          isFasting: true,
          elapsedSeconds: 8 * 3600,
          targetSeconds: 16 * 3600,
          isOvertime: false);
      expect(d.state, HubRingState.active);
      expect(d.value, closeTo(0.5, 0.001));
      expect(d.centerValue, '8:00'); // 8h remaining
      expect(d.centerLabel, 'LEFT');
    });

    test('overtime fills fully', () {
      final d = HubRings.fast(
          isFasting: true,
          elapsedSeconds: 17 * 3600,
          targetSeconds: 16 * 3600,
          isOvertime: true);
      expect(d.value, 1);
      expect(d.caption, 'Goal reached');
    });
  });

  group('HubRings.food', () {
    test('idle when nothing logged', () {
      final d = HubRings.food(calories: 0, goal: 2000);
      expect(d.state, HubRingState.idle);
    });

    test('active shows remaining', () {
      final d = HubRings.food(calories: 500, goal: 2000);
      expect(d.state, HubRingState.active);
      expect(d.value, closeTo(0.25, 0.001));
      expect(d.centerValue, '1,500');
      expect(d.centerLabel, 'LEFT');
    });

    test('over-goal flips to danger with amount over', () {
      final d = HubRings.food(calories: 2312, goal: 2000);
      expect(d.state, HubRingState.over);
      expect(d.isOver, isTrue);
      expect(d.value, 1);
      expect(d.centerValue, '+312');
      expect(d.centerLabel, 'OVER');
    });
  });

  group('HubRings.move', () {
    test('idle when no steps', () {
      final d = HubRings.move(steps: 0, goal: 8000);
      expect(d.state, HubRingState.idle);
    });

    test('active shows steps + progress', () {
      final d = HubRings.move(steps: 4000, goal: 8000);
      expect(d.state, HubRingState.active);
      expect(d.value, closeTo(0.5, 0.001));
      expect(d.centerValue, '4,000');
      expect(d.centerLabel, 'STEPS');
    });

    test('clamps over 100%', () {
      final d = HubRings.move(steps: 20000, goal: 8000);
      expect(d.value, 1);
    });
  });
}
