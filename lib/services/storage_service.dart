import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fasting_log.dart';
import '../models/quest.dart';

class StorageService {
  static const String keyIsFasting = 'isFasting';
  static const String keyStartTime = 'startTime';
  static const String keyEatingStartTime = 'eatingStartTime';
  static const String keyElapsedSeconds = 'elapsedSeconds';
  static const String keyFastingGoalHours = 'fastingGoalHours';
  static const String keyHistory = 'history';
  static const String keyQuests = 'quests';

  Future<void> saveState({
    required bool isFasting,
    DateTime? startTime,
    DateTime? eatingStartTime,
    required int elapsedSeconds,
    required int fastingGoalHours,
    required List<FastingLog> history,
    required List<Quest> quests,
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

    await prefs.setInt(keyElapsedSeconds, elapsedSeconds);
    await prefs.setInt(keyFastingGoalHours, fastingGoalHours);

    final historyJson = jsonEncode(history.map((e) => e.toJson()).toList());
    await prefs.setString(keyHistory, historyJson);

    final questsJson = jsonEncode(quests.map((e) => e.toJson()).toList());
    await prefs.setString(keyQuests, questsJson);
  }

  Future<Map<String, dynamic>> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    
    bool isFasting = prefs.getBool(keyIsFasting) ?? false;
    
    String? startTimeStr = prefs.getString(keyStartTime);
    DateTime? startTime = startTimeStr != null ? DateTime.parse(startTimeStr) : null;
    
    String? eatingStartTimeStr = prefs.getString(keyEatingStartTime);
    DateTime? eatingStartTime = eatingStartTimeStr != null ? DateTime.parse(eatingStartTimeStr) : null;
    
    int elapsedSeconds = prefs.getInt(keyElapsedSeconds) ?? 0;
    int fastingGoalHours = prefs.getInt(keyFastingGoalHours) ?? 16;
    
    String? historyJson = prefs.getString(keyHistory);
    List<FastingLog> history = [];
    if (historyJson != null) {
      try {
        List<dynamic> list = jsonDecode(historyJson);
        history = list.map((e) => FastingLog.fromJson(e)).toList();
      } catch (e) {
        print("Error parsing history: $e");
      }
    }
    
    String? questsJson = prefs.getString(keyQuests);
    List<Quest> quests = [];
    if (questsJson != null) {
      try {
        List<dynamic> list = jsonDecode(questsJson);
        quests = list.map((e) => Quest.fromJson(e)).toList();
      } catch (e) {
        print("Error parsing quests: $e");
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
    };
  }
}
