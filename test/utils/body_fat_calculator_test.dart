import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/body_fat_calculator.dart';

void main() {
  group('estimateBodyFatPercent', () {
    group('male', () {
      test('returns plausible BF% for typical male measurements', () {
        final bf = estimateBodyFatPercent(
          sex: 'male',
          heightCm: 175,
          waistCm: 85,
          neckCm: 38,
        );
        expect(bf, isNotNull);
        expect(bf!, inInclusiveRange(10.0, 22.0));
      });

      test('returns null when waist <= neck', () {
        expect(
          estimateBodyFatPercent(
              sex: 'male', heightCm: 175, waistCm: 38, neckCm: 38),
          isNull,
        );
        expect(
          estimateBodyFatPercent(
              sex: 'male', heightCm: 175, waistCm: 37, neckCm: 38),
          isNull,
        );
      });

      test('returns null when height <= 0', () {
        expect(
          estimateBodyFatPercent(
              sex: 'male', heightCm: 0, waistCm: 85, neckCm: 38),
          isNull,
        );
      });

      test('clamps result to [3, 60]', () {
        // Extreme inputs still stay in valid range
        final low = estimateBodyFatPercent(
          sex: 'male',
          heightCm: 200,
          waistCm: 60,
          neckCm: 55,
        );
        final high = estimateBodyFatPercent(
          sex: 'male',
          heightCm: 150,
          waistCm: 130,
          neckCm: 30,
        );
        expect(low, greaterThanOrEqualTo(3.0));
        expect(high, lessThanOrEqualTo(60.0));
      });
    });

    group('female', () {
      test('returns plausible BF% for typical female measurements', () {
        final bf = estimateBodyFatPercent(
          sex: 'female',
          heightCm: 165,
          waistCm: 75,
          neckCm: 33,
          hipsCm: 98,
        );
        expect(bf, isNotNull);
        expect(bf!, inInclusiveRange(20.0, 35.0));
      });

      test('returns null when hips is missing', () {
        expect(
          estimateBodyFatPercent(
              sex: 'female', heightCm: 165, waistCm: 75, neckCm: 33),
          isNull,
        );
      });

      test('returns null when waist + hips - neck <= 0', () {
        expect(
          estimateBodyFatPercent(
              sex: 'female',
              heightCm: 165,
              waistCm: 10,
              neckCm: 60,
              hipsCm: 10),
          isNull,
        );
      });
    });
  });
}
