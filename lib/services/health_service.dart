import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

class HealthService {
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.WORKOUT,
  ];

  static const _permissions = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  Future<bool> isAvailable() async {
    try {
      final result = await Health().isHealthConnectAvailable();
      debugPrint('HealthService: isAvailable=$result');
      return result;
    } catch (e) {
      debugPrint('HealthService: isAvailable error: $e');
      return false;
    }
  }

  Future<bool> hasPermissions() async {
    try {
      final result =
          await Health().hasPermissions(_types, permissions: _permissions);
      debugPrint('HealthService: hasPermissions=$result');
      return result ?? false;
    } catch (e) {
      debugPrint('HealthService: hasPermissions error: $e');
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    try {
      debugPrint('HealthService: configure()...');
      await Health().configure();
      debugPrint('HealthService: requestAuthorization() launching...');
      final result = await Health()
          .requestAuthorization(_types, permissions: _permissions);
      debugPrint('HealthService: requestAuthorization() result=$result');
      return result;
    } catch (e, st) {
      debugPrint('HealthService: requestPermissions error: $e\n$st');
      return false;
    }
  }

  static const _channel = MethodChannel('com.nudgr.app/health_connect');

  Future<void> openHealthConnectSettings() async {
    try {
      await _channel.invokeMethod('openPermissionsSettings');
    } catch (e) {
      debugPrint('HealthService: openHealthConnectSettings error: $e');
    }
  }

  Future<int> readTodaySteps({String? sourceId}) async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final total = await _sumTypeForRange(HealthDataType.STEPS, midnight, now,
          sourceId: sourceId);
      return total?.round() ?? 0;
    } catch (e) {
      debugPrint('HealthService: readTodaySteps error: $e');
      return 0;
    }
  }

  Future<double?> readTodayActiveCalories({String? sourceId}) async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      return await _sumTypeForRange(
          HealthDataType.ACTIVE_ENERGY_BURNED, midnight, now,
          sourceId: sourceId);
    } catch (e) {
      debugPrint('HealthService: readTodayActiveCalories error: $e');
      return null;
    }
  }

  Future<double?> readTodayTotalCalories({String? sourceId}) async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      return await _sumTypeForRange(
          HealthDataType.TOTAL_CALORIES_BURNED, midnight, now,
          sourceId: sourceId);
    } catch (e) {
      debugPrint('HealthService: readTodayTotalCalories error: $e');
      return null;
    }
  }

  Future<double?> readTodayDistance({String? sourceId}) async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      return await _sumTypeForRange(
          HealthDataType.DISTANCE_DELTA, midnight, now,
          sourceId: sourceId);
    } catch (e) {
      debugPrint('HealthService: readTodayDistance error: $e');
      return null;
    }
  }

  /// Reads today's workout sessions (e.g. from Strava) and sums totalDistance.
  /// GPS-accurate — preferred over DISTANCE_DELTA which device sensors don't populate.
  Future<double?> readTodayWorkoutDistance() async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final pts = await Health().getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: [HealthDataType.WORKOUT],
      );
      if (pts.isEmpty) return null;
      final total = pts.fold<double>(
        0.0,
        (sum, p) => sum + (p.workoutSummary?.totalDistance.toDouble() ?? 0.0),
      );
      debugPrint('HealthService: readTodayWorkoutDistance total=${total}m from ${pts.length} sessions');
      return total > 0 ? total : null;
    } catch (e) {
      debugPrint('HealthService: readTodayWorkoutDistance error: $e');
      return null;
    }
  }

  /// Reads steps, active calories, and distance for a specific past calendar day.
  /// [stepsSourceId] filters steps to a single source to prevent double-counting.
  Future<
      ({
        int steps,
        double? activeCalories,
        double? totalCalories,
        double? distance
      })> readDayData(
    DateTime date, {
    String? stepsSourceId,
  }) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    try {
      final steps = await _sumTypeForRange(HealthDataType.STEPS, start, end,
          sourceId: stepsSourceId);
      final activeCalories = await _sumTypeForRange(
          HealthDataType.ACTIVE_ENERGY_BURNED, start, end);
      final totalCalories = await _sumTypeForRange(
          HealthDataType.TOTAL_CALORIES_BURNED, start, end);
      final distance =
          await _sumTypeForRange(HealthDataType.DISTANCE_DELTA, start, end);
      return (
        steps: steps?.round() ?? 0,
        activeCalories: activeCalories,
        totalCalories: totalCalories,
        distance: distance
      );
    } catch (e) {
      debugPrint(
          'HealthService: readDayData(${DateFormat('yyyy-MM-dd').format(date)}) error: $e');
      return (
        steps: 0,
        activeCalories: null,
        totalCalories: null,
        distance: null
      );
    }
  }

  /// Fetches all data for [start]..[end] in exactly 4 API calls (one per type)
  /// and returns a map of dateKey → daily totals. Use this for backfill instead
  /// of per-day calls to avoid Health Connect API quota exhaustion.
  Future<
      Map<
          String,
          ({
            int steps,
            double? activeCalories,
            double? totalCalories,
            double? distance
          })>> readRangeDataByDay(
    DateTime start,
    DateTime end, {
    String? stepsSourceId,
  }) async {
    final steps = <String, int>{};
    final activeCalories = <String, double>{};
    final totalCalories = <String, double>{};
    final distance = <String, double>{};

    try {
      // STEPS — 1 API call for entire range
      final stepsPoints = await Health().getHealthDataFromTypes(
          startTime: start, endTime: end, types: [HealthDataType.STEPS]);
      final stepsFiltered = stepsSourceId != null
          ? stepsPoints.where((p) => p.sourceName == stepsSourceId).toList()
          : Health().removeDuplicates(stepsPoints);
      // Log per-source totals to diagnose double-counting
      final sourceTotals = <String, int>{};
      for (final p in stepsPoints) {
        sourceTotals[p.sourceName] = (sourceTotals[p.sourceName] ?? 0) +
            (p.value as NumericHealthValue).numericValue.toInt();
      }
      debugPrint(
          'HealthService[STEPS] range source totals: $sourceTotals | filtering by: $stepsSourceId');
      for (final p in stepsFiltered) {
        final day = _dayKey(p.dateFrom.toLocal());
        steps[day] = (steps[day] ?? 0) +
            (p.value as NumericHealthValue).numericValue.toInt();
      }
    } catch (e) {
      debugPrint('HealthService: readRangeDataByDay STEPS error: $e');
    }

    try {
      // ACTIVE CALORIES — 1 API call
      final pts = Health().removeDuplicates(await Health()
          .getHealthDataFromTypes(
              startTime: start,
              endTime: end,
              types: [HealthDataType.ACTIVE_ENERGY_BURNED]));
      for (final p in pts) {
        final day = _dayKey(p.dateFrom.toLocal());
        activeCalories[day] = (activeCalories[day] ?? 0.0) +
            (p.value as NumericHealthValue).numericValue.toDouble();
      }
    } catch (e) {
      debugPrint('HealthService: readRangeDataByDay ACTIVE_CALORIES error: $e');
    }

    try {
      // TOTAL CALORIES — 1 API call
      final pts = Health().removeDuplicates(await Health()
          .getHealthDataFromTypes(
              startTime: start,
              endTime: end,
              types: [HealthDataType.TOTAL_CALORIES_BURNED]));
      for (final p in pts) {
        final day = _dayKey(p.dateFrom.toLocal());
        totalCalories[day] = (totalCalories[day] ?? 0.0) +
            (p.value as NumericHealthValue).numericValue.toDouble();
      }
    } catch (e) {
      debugPrint('HealthService: readRangeDataByDay TOTAL_CALORIES error: $e');
    }

    try {
      // DISTANCE — 1 API call
      final pts = Health().removeDuplicates(await Health()
          .getHealthDataFromTypes(
              startTime: start,
              endTime: end,
              types: [HealthDataType.DISTANCE_DELTA]));
      for (final p in pts) {
        final day = _dayKey(p.dateFrom.toLocal());
        distance[day] = (distance[day] ?? 0.0) +
            (p.value as NumericHealthValue).numericValue.toDouble();
      }
    } catch (e) {
      debugPrint('HealthService: readRangeDataByDay DISTANCE error: $e');
    }

    // WORKOUT SESSIONS — 1 API call (GPS-based, e.g. Strava).
    // totalDistance from workoutSummary is preferred over DISTANCE_DELTA since
    // device sensors don't populate DISTANCE_DELTA.
    final workoutDistance = <String, double>{};
    try {
      final pts = await Health().getHealthDataFromTypes(
          startTime: start, endTime: end, types: [HealthDataType.WORKOUT]);
      for (final p in pts) {
        final d = p.workoutSummary?.totalDistance.toDouble() ?? 0.0;
        if (d <= 0) continue;
        final day = _dayKey(p.dateFrom.toLocal());
        workoutDistance[day] = (workoutDistance[day] ?? 0.0) + d;
      }
      debugPrint(
          'HealthService: readRangeDataByDay WORKOUT distance days=${workoutDistance.length}');
    } catch (e) {
      debugPrint('HealthService: readRangeDataByDay WORKOUT error: $e');
    }

    // Merge all keys
    final allDays = {
      ...steps.keys,
      ...activeCalories.keys,
      ...totalCalories.keys,
      ...distance.keys,
      ...workoutDistance.keys,
    };
    return {
      for (final day in allDays)
        day: (
          steps: steps[day] ?? 0,
          activeCalories: activeCalories[day],
          totalCalories: totalCalories[day],
          // Prefer GPS workout distance; fall back to DISTANCE_DELTA
          distance: workoutDistance[day] ?? distance[day],
        ),
    };
  }

  String _dayKey(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  /// Returns distinct step data sources seen in the last 7 days.
  /// Each entry is (sourceId, sourceName).
  Future<List<({String sourceId, String sourceName})>> readStepSources() async {
    try {
      final end = DateTime.now();
      final start = end.subtract(const Duration(days: 7));
      final data = await Health().getHealthDataFromTypes(
        startTime: start,
        endTime: end,
        types: [HealthDataType.STEPS],
      );
      final seen = <String>{};
      final sources = <({String sourceId, String sourceName})>[];
      for (final p in data) {
        // Use sourceName as the stable identifier — sourceId is empty on Health Connect Android
        if (seen.add(p.sourceName)) {
          sources.add((sourceId: p.sourceName, sourceName: p.sourceName));
        }
      }
      return sources;
    } catch (e) {
      debugPrint('HealthService: readStepSources error: $e');
      return [];
    }
  }

  /// Sums all Health Connect data points for [type] within [start]..[end].
  /// If [sourceId] is provided, only data from that source is summed.
  /// Returns null if no data is available for that range.
  Future<double?> _sumTypeForRange(
    HealthDataType type,
    DateTime start,
    DateTime end, {
    String? sourceId,
  }) async {
    final data = await Health().getHealthDataFromTypes(
      startTime: start,
      endTime: end,
      types: [type],
    );
    if (data.isEmpty) return null;
    if (type == HealthDataType.STEPS || type == HealthDataType.DISTANCE_DELTA) {
      final sourceTotals = <String, double>{};
      for (final p in data) {
        sourceTotals[p.sourceName] = (sourceTotals[p.sourceName] ?? 0) +
            (p.value as NumericHealthValue).numericValue.toDouble();
      }
      debugPrint(
          'HealthService[$type] source totals: $sourceTotals | filtering by: $sourceId');
    }
    final filtered = sourceId != null
        ? data.where((p) => p.sourceName == sourceId).toList()
        : Health().removeDuplicates(data);
    debugPrint(
        'HealthService[$type] raw=${data.length} deduped=${filtered.length}');
    if (filtered.isEmpty) return null;
    return filtered.fold<double>(
      0,
      (sum, p) => sum + (p.value as NumericHealthValue).numericValue.toDouble(),
    );
  }
}
