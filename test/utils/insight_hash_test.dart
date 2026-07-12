import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/insight_hash.dart';

void main() {
  group('hashMarkers', () {
    test('same map, different key insertion order → same hash', () {
      final a = {'streak': 3, 'isFasting': true, 'goalHours': 16};
      final b = {'goalHours': 16, 'isFasting': true, 'streak': 3};
      expect(hashMarkers(a), hashMarkers(b));
    });

    test('nested maps are also order-independent', () {
      final a = {
        'section': {'b': 2, 'a': 1}
      };
      final b = {
        'section': {'a': 1, 'b': 2}
      };
      expect(hashMarkers(a), hashMarkers(b));
    });

    test('different values → different hash', () {
      final a = {'todayCalories': 2000};
      final b = {'todayCalories': 2100};
      expect(hashMarkers(a), isNot(hashMarkers(b)));
    });

    test('different keys → different hash', () {
      final a = {'streak': 3};
      final b = {'streakCount': 3};
      expect(hashMarkers(a), isNot(hashMarkers(b)));
    });

    test('is stable across repeated calls (no per-run seed)', () {
      final data = {'level': 5, 'xp': 120, 'hp': 80};
      expect(hashMarkers(data), hashMarkers(Map.of(data)));
    });
  });

  group('roundKcal', () {
    test('rounds to the nearest whole calorie', () {
      expect(roundKcal(2000.4), 2000);
      expect(roundKcal(2000.6), 2001);
    });

    test('collapses jitter so hashes of the rounded values match', () {
      final a = {'todayCalories': roundKcal(2000.4)};
      final b = {'todayCalories': roundKcal(2000.44)};
      expect(hashMarkers(a), hashMarkers(b));
    });
  });

  group('roundKg', () {
    test('rounds to one decimal place', () {
      expect(roundKg(70.14), closeTo(70.1, 1e-9));
      expect(roundKg(70.16), closeTo(70.2, 1e-9));
    });

    test('collapses sub-decimal jitter so hashes match', () {
      final a = {'latestWeightKg': roundKg(70.141)};
      final b = {'latestWeightKg': roundKg(70.143)};
      expect(hashMarkers(a), hashMarkers(b));
    });
  });

  group('roundCurrency', () {
    test('rounds to the nearest whole unit', () {
      expect(roundCurrency(1999.4), 1999);
      expect(roundCurrency(1999.6), 2000);
    });

    test('collapses jitter so hashes of the rounded values match', () {
      final a = {'monthSpent': roundCurrency(15000.2)};
      final b = {'monthSpent': roundCurrency(15000.49)};
      expect(hashMarkers(a), hashMarkers(b));
    });
  });

  group('canonicalize', () {
    test('produces sorted-key JSON regardless of input order', () {
      final a = canonicalize({'b': 2, 'a': 1});
      final b = canonicalize({'a': 1, 'b': 2});
      expect(a, b);
      expect(a, '{"a":1,"b":2}');
    });
  });
}
