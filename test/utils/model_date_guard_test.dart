import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/model_date_guard.dart';

/// The model resolves "Sept 24" against its training year. These pin the
/// client-side clamp: a slipped year comes back to the user's, and a date the
/// user plausibly meant is never touched.
void main() {
  // Fixed so nothing depends on the day the suite runs.
  final now = DateTime(2026, 9, 30, 10);

  group('rebaseStaleDate', () {
    test('the bug: "Sept 24" said on Sept 30 lands in 2024, comes back', () {
      expect(
          rebaseStaleDate(DateTime(2024, 9, 24), now), DateTime(2026, 9, 24));
    });

    test('recent dates are left exactly as given', () {
      expect(
          rebaseStaleDate(DateTime(2026, 9, 24), now), DateTime(2026, 9, 24));
      expect(rebaseStaleDate(DateTime(2026, 1, 3), now), DateTime(2026, 1, 3));
      // Last December is still well inside the window.
      expect(
          rebaseStaleDate(DateTime(2025, 12, 20), now), DateTime(2025, 12, 20));
    });

    test('a slipped date that would land in the future goes back one more year',
        () {
      // "Dec 20" meant last December, not three months from now.
      expect(
          rebaseStaleDate(DateTime(2024, 12, 20), now), DateTime(2025, 12, 20));
    });

    test('a payback date may move into the future', () {
      expect(rebaseStaleDate(DateTime(2024, 12, 20), now, allowFuture: true),
          DateTime(2026, 12, 20));
    });

    test('Feb 29 clamps instead of rolling into March', () {
      expect(
          rebaseStaleDate(DateTime(2024, 2, 29), now), DateTime(2026, 2, 28));
    });
  });

  group('rebaseStaleMonthKey', () {
    test('a slipped month comes back to this year', () {
      expect(rebaseStaleMonthKey('2024-09', now), '2026-09');
    });

    test('a month just ahead stays ahead', () {
      // "a bill in November" planned from September.
      expect(rebaseStaleMonthKey('2024-11', now), '2026-11');
    });

    test('a month that would be most of a year ahead goes to last year', () {
      expect(rebaseStaleMonthKey('2023-12', DateTime(2026, 2, 10)), '2025-12');
    });

    test('recent and future months are untouched', () {
      expect(rebaseStaleMonthKey('2026-09', now), '2026-09');
      expect(rebaseStaleMonthKey('2025-11', now), '2025-11');
      expect(rebaseStaleMonthKey('2027-01', now), '2027-01');
    });

    test('anything not shaped like YYYY-MM is returned as-is', () {
      expect(rebaseStaleMonthKey('September', now), 'September');
      expect(rebaseStaleMonthKey('2024-13', now), '2024-13');
    });
  });
}
