import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/body_measurement_entry.dart';

void main() {
  final loggedAt = DateTime(2026, 5, 1, 8, 0);

  BodyMeasurementEntry entry0({
    String id = 'e1',
    double? waistCm = 85.0,
    double? neckCm = 38.0,
    double? hipsCm,
    double? chestCm,
    double? bicepCm,
    double? thighCm,
    String? notes,
  }) =>
      BodyMeasurementEntry(
        id: id,
        loggedAt: loggedAt,
        waistCm: waistCm,
        neckCm: neckCm,
        hipsCm: hipsCm,
        chestCm: chestCm,
        bicepCm: bicepCm,
        thighCm: thighCm,
        notes: notes,
      );

  group('BodyMeasurementEntry', () {
    group('fromJson / toJson roundtrip', () {
      test('all fields present', () {
        final entry = entry0(
          waistCm: 85.5,
          neckCm: 38.2,
          hipsCm: 95.0,
          chestCm: 100.0,
          bicepCm: 32.0,
          thighCm: 55.0,
          notes: 'morning',
        );
        final roundtripped = BodyMeasurementEntry.fromJson(entry.toJson());
        expect(roundtripped.id, entry.id);
        expect(roundtripped.loggedAt, entry.loggedAt);
        expect(roundtripped.waistCm, entry.waistCm);
        expect(roundtripped.neckCm, entry.neckCm);
        expect(roundtripped.hipsCm, entry.hipsCm);
        expect(roundtripped.chestCm, entry.chestCm);
        expect(roundtripped.bicepCm, entry.bicepCm);
        expect(roundtripped.thighCm, entry.thighCm);
        expect(roundtripped.notes, entry.notes);
      });

      test('optional fields null survive roundtrip', () {
        final entry = entry0(hipsCm: null, chestCm: null, notes: null);
        final rt = BodyMeasurementEntry.fromJson(entry.toJson());
        expect(rt.hipsCm, isNull);
        expect(rt.chestCm, isNull);
        expect(rt.notes, isNull);
      });

      test('loggedAt is preserved as ISO 8601', () {
        final json = entry0().toJson();
        expect(json['loggedAt'], loggedAt.toIso8601String());
      });
    });

    group('copyWith', () {
      test('overrides specified fields, keeps others', () {
        final original = entry0(waistCm: 85.0, neckCm: 38.0);
        final updated = original.copyWith(waistCm: 84.5);
        expect(updated.waistCm, 84.5);
        expect(updated.neckCm, original.neckCm);
        expect(updated.id, original.id);
        expect(updated.loggedAt, original.loggedAt);
      });
    });
  });
}
