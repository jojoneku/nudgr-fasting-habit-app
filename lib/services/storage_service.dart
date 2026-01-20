import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fasting_log.dart';
import '../models/quest.dart';
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
