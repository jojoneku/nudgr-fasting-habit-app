import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_goals.dart';
import '../models/activity_log.dart';
import '../models/daily_nutrition_log.dart';
import '../models/fasting_log.dart';
import '../models/food_template.dart';
import '../models/nutrition_goals.dart';
import '../models/quest.dart';
import '../models/tdee_profile.dart';
import '../models/user_stats.dart';

class StorageService {
  static const String keyIsFasting = 'isFasting';
  static const String keyStartTime = 'startTime';
  static const String keyEatingStartTime = 'eatingStartTime';
  static const String keyElapsedSeconds = 'elapsedSeconds';
  static const String keyFastingGoalHours = 'fastingGoalHours';
  static const String keyHistory = 'history';
  static const String keyQuests = 'quests';
  static const String keyUserStats = 'userStats';
  static const String keyLastPenaltyCheckDate = 'lastPenaltyCheckDate';

  Future<void> saveUserStats(UserStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    final statsJson = jsonEncode(stats.toJson());
    await prefs.setString(keyUserStats, statsJson);
    debugPrint('StorageService: UserStats saved. Level=${stats.level}');
  }

  Future<UserStats> loadUserStats() async {
    final prefs = await SharedPreferences.getInstance();
    final statsJson = prefs.getString(keyUserStats);
    if (statsJson != null) {
      try {
        return UserStats.fromJson(jsonDecode(statsJson));
      } catch (e) {
        debugPrint('StorageService: Error parsing UserStats: $e');
      }
    }
    return UserStats.initial();
  }

  Future<void> saveState({
    required bool isFasting,
    DateTime? startTime,
    DateTime? eatingStartTime,
    required int elapsedSeconds,
    required int fastingGoalHours,
    required List<FastingLog> history,
    required List<Quest> quests,
    DateTime? lastPenaltyCheckDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyIsFasting, isFasting);
    if (startTime != null) {
      await prefs.setString(keyStartTime, startTime.toIso8601String());
    } else {
      await prefs.remove(keyStartTime);
    }
    
    if (eatingStartTime != null) {
      await prefs.setString(keyEatingStartTime, eatingStartTime.toIso8601String());
    } else {
      await prefs.remove(keyEatingStartTime);
    }

    if (lastPenaltyCheckDate != null) {
      await prefs.setString(keyLastPenaltyCheckDate, lastPenaltyCheckDate.toIso8601String());
    }

    await prefs.setInt(keyElapsedSeconds, elapsedSeconds);
    await prefs.setInt(keyFastingGoalHours, fastingGoalHours);

    final historyJson = jsonEncode(history.map((e) => e.toJson()).toList());
    await prefs.setString(keyHistory, historyJson);

    final questsJson = jsonEncode(quests.map((e) => e.toJson()).toList());
    await prefs.setString(keyQuests, questsJson);
    debugPrint('StorageService: State saved. isFasting=$isFasting');
  }

  Future<Map<String, dynamic>> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force reload from disk
    
    bool isFasting = prefs.getBool(keyIsFasting) ?? false;
    debugPrint('StorageService: Loaded isFasting=$isFasting');
    
    String? startTimeStr = prefs.getString(keyStartTime);
    DateTime? startTime = startTimeStr != null ? DateTime.parse(startTimeStr) : null;
    
    String? eatingStartTimeStr = prefs.getString(keyEatingStartTime);
    DateTime? eatingStartTime = eatingStartTimeStr != null ? DateTime.parse(eatingStartTimeStr) : null;
    
    String? lastPenaltyCheckDateStr = prefs.getString(keyLastPenaltyCheckDate);
    DateTime? lastPenaltyCheckDate = lastPenaltyCheckDateStr != null ? DateTime.parse(lastPenaltyCheckDateStr) : null;

    int elapsedSeconds = prefs.getInt(keyElapsedSeconds) ?? 0;
    int fastingGoalHours = prefs.getInt(keyFastingGoalHours) ?? 16;
    
    String? historyJson = prefs.getString(keyHistory);
    List<FastingLog> history = [];
    if (historyJson != null) {
      try {
        List<dynamic> list = jsonDecode(historyJson);
        history = list.map((e) => FastingLog.fromJson(e)).toList();
      } catch (e) {
        // Error parsing history
      }
    }
    
    String? questsJson = prefs.getString(keyQuests);
    List<Quest> quests = [];
    if (questsJson != null) {
      try {
        List<dynamic> list = jsonDecode(questsJson);
        quests = list.map((e) => Quest.fromJson(e)).toList();
      } catch (e) {
        // Error parsing quests
      }
    }

    return {
      'isFasting': isFasting,
      'startTime': startTime,
      'eatingStartTime': eatingStartTime,
      'elapsedSeconds': elapsedSeconds,
      'fastingGoalHours': fastingGoalHours,
      'history': history,
      'quests': quests,
      'lastPenaltyCheckDate': lastPenaltyCheckDate,
    };
  }

  // ─── Nutrition ───────────────────────────────────────────────────────────────

  static const String keyNutritionLogs = 'nutritionLogs';
  static const String keyNutritionGoals = 'nutritionGoals';
  static const String keyNutritionStreak = 'nutritionStreak';
  static const String keyNutritionGoalMetDate = 'nutritionGoalMetDate';

  Future<void> saveNutritionLog(DailyNutritionLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyNutritionLogs);
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[log.date] = log.toJson();
    await prefs.setString(keyNutritionLogs, jsonEncode(all));
  }

  Future<DailyNutritionLog> loadTodayNutritionLog() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final raw = prefs.getString(keyNutritionLogs);
    if (raw != null) {
      try {
        final Map<String, dynamic> all =
            jsonDecode(raw) as Map<String, dynamic>;
        if (all.containsKey(todayKey)) {
          return DailyNutritionLog.fromJson(
              all[todayKey] as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint('StorageService: Error loading today nutrition log: $e');
      }
    }
    return DailyNutritionLog.empty(todayKey);
  }

  Future<List<DailyNutritionLog>> loadNutritionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyNutritionLogs);
    if (raw == null) return [];
    try {
      final Map<String, dynamic> all =
          jsonDecode(raw) as Map<String, dynamic>;
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final logs = all.entries
          .where((e) => e.key != todayKey)
          .map((e) =>
              DailyNutritionLog.fromJson(e.value as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return logs.take(30).toList();
    } catch (e) {
      debugPrint('StorageService: Error loading nutrition history: $e');
      return [];
    }
  }

  Future<void> saveNutritionGoals(NutritionGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyNutritionGoals, jsonEncode(goals.toJson()));
  }

  Future<NutritionGoals> loadNutritionGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyNutritionGoals);
    if (raw != null) {
      try {
        return NutritionGoals.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('StorageService: Error loading nutrition goals: $e');
      }
    }
    return NutritionGoals.initial();
  }

  Future<void> saveNutritionStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyNutritionStreak, streak);
  }

  Future<int> loadNutritionStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyNutritionStreak) ?? 0;
  }

  Future<void> saveNutritionGoalMetDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyNutritionGoalMetDate, date);
  }

  Future<String?> loadNutritionGoalMetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyNutritionGoalMetDate);
  }

  // ─── Nutrition v2 — TDEE, food library, log streak ───────────────────────────

  static const String keyTdeeProfile  = 'tdeeProfile';
  static const String keyFoodLibrary  = 'foodLibrary';
  static const String keyLogStreak    = 'nutritionLogStreak';
  static const String keyLogStreakDate = 'nutritionLogStreakDate';

  Future<void> saveTdeeProfile(TdeeProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyTdeeProfile, jsonEncode(profile.toJson()));
  }

  Future<TdeeProfile?> loadTdeeProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyTdeeProfile);
    if (raw == null) return null;
    try {
      return TdeeProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('StorageService: Error loading TdeeProfile: $e');
      return null;
    }
  }

  Future<void> saveFoodLibrary(List<FoodTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(templates.map((t) => t.toJson()).toList());
    await prefs.setString(keyFoodLibrary, json);
  }

  Future<List<FoodTemplate>> loadFoodLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyFoodLibrary);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => FoodTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading food library: $e');
      return [];
    }
  }

  Future<void> saveLogStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyLogStreak, streak);
  }

  Future<int> loadLogStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyLogStreak) ?? 0;
  }

  Future<void> saveLogStreakDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLogStreakDate, date);
  }

  Future<String?> loadLogStreakDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLogStreakDate);
  }

  // ─── Activity ────────────────────────────────────────────────────────────────

  static const String keyActivityLogs = 'activityLogs';
  static const String keyActivityGoals = 'activityGoals';
  static const String keyActivityGoalMetDate = 'activityGoalMetDate';
  static const String keyActivityStreak = 'activityStreak';

  Future<void> saveActivityLog(ActivityLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActivityLogs);
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[log.date] = log.toJson();
    await prefs.setString(keyActivityLogs, jsonEncode(all));
  }

  Future<ActivityLog> loadTodayActivityLog() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final raw = prefs.getString(keyActivityLogs);
    if (raw != null) {
      try {
        final Map<String, dynamic> all =
            jsonDecode(raw) as Map<String, dynamic>;
        if (all.containsKey(todayKey)) {
          return ActivityLog.fromJson(all[todayKey] as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint('StorageService: Error loading today activity log: $e');
      }
    }
    return ActivityLog.empty(todayKey);
  }

  Future<List<ActivityLog>> loadActivityHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActivityLogs);
    if (raw == null) return [];
    try {
      final Map<String, dynamic> all =
          jsonDecode(raw) as Map<String, dynamic>;
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final logs = all.entries
          .where((e) => e.key != todayKey)
          .map((e) => ActivityLog.fromJson(e.value as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return logs.take(30).toList();
    } catch (e) {
      debugPrint('StorageService: Error loading activity history: $e');
      return [];
    }
  }

  Future<void> saveActivityGoals(ActivityGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyActivityGoals, jsonEncode(goals.toJson()));
  }

  Future<ActivityGoals> loadActivityGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActivityGoals);
    if (raw != null) {
      try {
        return ActivityGoals.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('StorageService: Error loading activity goals: $e');
      }
    }
    return ActivityGoals.initial();
  }

  Future<void> saveActivityGoalMetDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyActivityGoalMetDate, date);
  }

  Future<String?> loadActivityGoalMetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyActivityGoalMetDate);
  }

  Future<void> saveActivityStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyActivityStreak, streak);
  }

  Future<int> loadActivityStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyActivityStreak) ?? 0;
  }

  // ─── Export / Import ─────────────────────────────────────────────────────────

  Future<String> exportAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final allData = <String, dynamic>{};
    final keys = prefs.getKeys();
    
    for (String key in keys) {
      allData[key] = prefs.get(key);
    }
    
    return jsonEncode(allData);
  }

  Future<void> importAllData(String jsonString) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      
      // Clear existing first? Maybe safer to just overwrite.
      // But clearing ensures no stale keys remain.
      await prefs.clear();

      for (String key in data.keys) {
        final value = data[key];
        if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is String) {
          await prefs.setString(key, value);
        } else if (value is List) {
           await prefs.setStringList(key, List<String>.from(value));
        }
      }
      debugPrint('StorageService: Import successful. Keys: ${data.keys.toList()}');
    } catch (e) {
      debugPrint('StorageService: Import failed: $e');
      throw Exception('Invalid data format');
    }
  }
}
