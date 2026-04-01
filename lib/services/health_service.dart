import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class HealthService {
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_DELTA,
  ];

  static const _permissions = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  Future<bool> isAvailable() async {
    try {
      return await Health().isHealthConnectAvailable();
    } catch (e) {
      debugPrint('HealthService: isAvailable error: $e');
      return false;
    }
  }

  Future<bool> hasPermissions() async {
    try {
      final result = await Health().hasPermissions(_types, permissions: _permissions);
      return result ?? false;
    } catch (e) {
      debugPrint('HealthService: hasPermissions error: $e');
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    try {
      await Health().configure();
      return await Health().requestAuthorization(_types, permissions: _permissions);
    } catch (e) {
      debugPrint('HealthService: requestPermissions error: $e');
      return false;
    }
  }

  Future<int> readTodaySteps() async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final data = await Health().getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: [HealthDataType.STEPS],
      );
      final merged = Health().removeDuplicates(data);
      final total = merged.fold<double>(
        0,
        (sum, p) => sum + (p.value as NumericHealthValue).numericValue.toDouble(),
      );
      return total.round();
    } catch (e) {
      debugPrint('HealthService: readTodaySteps error: $e');
      return 0;
    }
  }

  Future<double?> readTodayActiveCalories() async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final data = await Health().getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
      );
      if (data.isEmpty) return null;
      final merged = Health().removeDuplicates(data);
      return merged.fold<double>(
        0,
        (sum, p) => sum + (p.value as NumericHealthValue).numericValue.toDouble(),
      );
    } catch (e) {
      debugPrint('HealthService: readTodayActiveCalories error: $e');
      return null;
    }
  }

  Future<double?> readTodayDistance() async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final data = await Health().getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: [HealthDataType.DISTANCE_DELTA],
      );
      if (data.isEmpty) return null;
      final merged = Health().removeDuplicates(data);
      return merged.fold<double>(
        0,
        (sum, p) => sum + (p.value as NumericHealthValue).numericValue.toDouble(),
      );
    } catch (e) {
      debugPrint('HealthService: readTodayDistance error: $e');
      return null;
    }
  }
}
