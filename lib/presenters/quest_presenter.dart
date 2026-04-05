import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/habit_routine.dart';
import '../models/quest.dart';
import '../models/quest_achievement.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'stats_presenter.dart';

/// Streak milestones that trigger badge unlocks and freeze awards.
const List<int> _streakMilestones = [7, 21, 30, 66, 100];

/// After this many consecutive completions on a stat-linked quest, +1 to that stat.
const int _statProgressThreshold = 21;

/// Maximum streak freezes a quest can hold.
const int _maxFreezes = 3;

/// Probability of a critical completion (2× XP).
const double _critChance = 0.15;

class QuestPresenter extends ChangeNotifier {
  final StorageService _storage;
  final StatsPresenter _stats;
  final NotificationService _notifications;

  List<Quest> _quests = [];
  List<HabitRoutine> _routines = [];
  List<QuestAchievement> _achievements = [];
  DateTime? _lastPenaltyCheckDate;

  final _random = Random();

  QuestPresenter({
    required StorageService storage,
    required StatsPresenter stats,
    NotificationService? notifications,
  })  : _storage = storage,
        _stats = stats,
        _notifications = notifications ?? NotificationService() {
    _init();
  }

  // ─── Public state ────────────────────────────────────────────────────────────

  List<Quest> get quests => List.unmodifiable(_quests);
  List<HabitRoutine> get routines => List.unmodifiable(_routines);
  List<QuestAchievement> get unseenAchievements =>
      _achievements.where((a) => !a.seen).toList();
  bool get hasUnseenAchievements => _achievements.any((a) => !a.seen);

  // ─── Daily grouping ──────────────────────────────────────────────────────────

  List<Quest> get todayActiveQuests {
    final now = DateTime.now();
    return _quests.where((q) {
      if (!q.isEnabled || !q.days[now.weekday - 1]) return false;
      final questTime =
          DateTime(now.year, now.month, now.day, q.hour, q.minute);
      return !q.isCompletedToday && !q.isPartialToday && questTime.isAfter(now);
    }).toList()
      ..sort(_byTime);
  }

  List<Quest> get todayOverdueQuests {
    final now = DateTime.now();
    return _quests.where((q) {
      if (!q.isEnabled || !q.days[now.weekday - 1]) return false;
      final questTime =
          DateTime(now.year, now.month, now.day, q.hour, q.minute);
      return !q.isCompletedToday &&
          !q.isPartialToday &&
          questTime.isBefore(now);
    }).toList()
      ..sort(_byTime);
  }

  List<Quest> get todayCompletedQuests {
    final now = DateTime.now();
    return _quests.where((q) {
      if (!q.isEnabled || !q.days[now.weekday - 1]) return false;
      return q.isCompletedToday || q.isPartialToday;
    }).toList()
      ..sort(_byTime);
  }

  /// Quests that belong to a routine scheduled for today.
  List<Quest> questsForRoutine(HabitRoutine routine) {
    return routine.questIds
        .map((id) => _quests.where((q) => q.id.toString() == id).firstOrNull)
        .whereType<Quest>()
        .toList();
  }

  /// Whether a grace completion is allowed (within 30 min after midnight).
  bool canGraceComplete(int questId) {
    final now = DateTime.now();
    final midnightToday = DateTime(now.year, now.month, now.day);
    final graceEnd = midnightToday.add(const Duration(minutes: 30));
    if (now.isAfter(graceEnd)) return false;

    final yesterday = midnightToday.subtract(const Duration(days: 1));
    final quest = _findQuestById(questId);
    if (quest == null) return false;
    if (quest.isCompletedOn(yesterday) || quest.isPartialOn(yesterday)) {
      return false; // Already logged yesterday
    }
    return quest.days[yesterday.weekday - 1];
  }

  /// 0.0–1.0 progress toward the 21-consecutive-day stat point for a quest.
  double statProgressFor(int questId) {
    final quest = _findQuestById(questId);
    if (quest == null || quest.linkedStat == null) return 0.0;
    return (quest.streakCount % _statProgressThreshold) /
        _statProgressThreshold;
  }

  // ─── Initialization ──────────────────────────────────────────────────────────

  Future<void> _init() async {
    _quests = (await _storage.loadQuests()).map(_backfillStreak).toList();
    _routines = await _storage.loadRoutines();
    _achievements = await _storage.loadAchievements();
    _lastPenaltyCheckDate = await _storage.loadQuestPenaltyCheckDate();
    notifyListeners();

    await _notifications.init();
    await checkMissedQuestsAndApplyPenalty();
    await _rescheduleAll();
    _scheduleStreakAtRiskIfNeeded();
  }

  /// On first load after model migration, recalculate streak from completedDates.
  Quest _backfillStreak(Quest q) {
    if (q.streakCount > 0 || q.completedDates.isEmpty) return q;
    return q.copyWith(streakCount: _calculateCurrentStreak(q));
  }

  Future<void> reload() async {
    _quests = (await _storage.loadQuests()).map(_backfillStreak).toList();
    notifyListeners();
  }

  // ─── Completion ──────────────────────────────────────────────────────────────

  /// Completes a quest. Returns (xpGained, isCritical).
  Future<(int, bool)> completeQuest(int questId,
      {CompletionType type = CompletionType.full, DateTime? date}) async {
    final idx = _indexById(questId);
    if (idx == -1) return (0, false);

    final quest = _quests[idx];
    final completionDate = date ?? DateTime.now();

    // Toggle off if already fully completed
    if (quest.isCompletedOn(completionDate)) {
      _quests[idx] = quest.copyWith(
        completedDates: List.from(quest.completedDates)
          ..remove(_dateKey(completionDate)),
      );
      notifyListeners();
      await _saveQuests();
      return (0, false);
    }

    final bool isCritical =
        type == CompletionType.full && _random.nextDouble() < _critChance;
    final int baseXp = type == CompletionType.partial
        ? (quest.xpReward / 2).round()
        : quest.xpReward;
    final int xpGained = isCritical ? baseXp * 2 : baseXp;

    // Award XP if not already awarded today
    if (!_xpAwardedToday(quest)) {
      await _stats.addXp(xpGained);
    }

    // Update completion lists
    final dateStr = _dateKey(completionDate);
    final newCompleted = List<String>.from(quest.completedDates);
    final newPartial = List<String>.from(quest.partialDates);

    if (type == CompletionType.full) {
      newCompleted.add(dateStr);
      newPartial.remove(dateStr);
    } else {
      newPartial.add(dateStr);
    }

    // Update streak
    final newStreak = type == CompletionType.full
        ? quest.streakCount + 1
        : quest.streakCount; // partial preserves streak but doesn't advance it

    final updated = quest.copyWith(
      completedDates: newCompleted,
      partialDates: newPartial,
      lastXpAwarded: DateTime.now(),
      streakCount: newStreak,
    );
    _quests[idx] = updated;

    // Check stat auto-progression (21-day threshold)
    if (updated.linkedStat != null &&
        updated.streakCount > 0 &&
        updated.streakCount % _statProgressThreshold == 0) {
      await _stats.awardStat(updated.linkedStat!.name);
    }

    // Check milestone achievements
    await _checkMilestones(updated);

    // One-time quest: delete after completion
    if (quest.isOneTime && type == CompletionType.full) {
      await deleteQuest(questId);
      return (xpGained, isCritical);
    }

    notifyListeners();
    await _saveQuests();
    await _storage.saveAchievements(_achievements);
    return (xpGained, isCritical);
  }

  /// Complete yesterday's quest within the 30-min grace window after midnight.
  Future<(int, bool)> graceCompleteQuest(int questId) async {
    if (!canGraceComplete(questId)) return (0, false);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return completeQuest(questId, date: yesterday);
  }

  // ─── Streak management ───────────────────────────────────────────────────────

  Future<void> spendStreakFreeze(int questId) async {
    final idx = _indexById(questId);
    if (idx == -1) return;
    final quest = _quests[idx];
    if (quest.streakFreezes <= 0) return;
    _quests[idx] = quest.copyWith(
      streakFreezes: quest.streakFreezes - 1,
    );
    notifyListeners();
    await _saveQuests();
  }

  // ─── CRUD ────────────────────────────────────────────────────────────────────

  Future<void> addQuest(Quest quest) async {
    _quests.add(quest);
    notifyListeners();
    if (quest.isEnabled) {
      await _notifications.scheduleQuestNotifications(quest);
    }
    await _saveQuests();
  }

  Future<void> updateQuest(Quest quest) async {
    final idx = _indexById(quest.id);
    if (idx == -1) return;
    await _notifications.cancelQuestNotifications(_quests[idx]);
    _quests[idx] = quest;
    notifyListeners();
    if (quest.isEnabled) {
      await _notifications.scheduleQuestNotifications(quest);
    }
    await _saveQuests();
  }

  Future<void> deleteQuest(int questId) async {
    final idx = _indexById(questId);
    if (idx == -1) return;
    await _notifications.cancelQuestNotifications(_quests[idx]);
    _quests.removeAt(idx);
    notifyListeners();
    await _saveQuests();
  }

  Future<void> toggleQuest(int questId, bool isEnabled) async {
    final idx = _indexById(questId);
    if (idx == -1) return;
    final quest = _quests[idx].copyWith(isEnabled: isEnabled);
    _quests[idx] = quest;
    notifyListeners();
    if (isEnabled) {
      await _notifications.scheduleQuestNotifications(quest);
    } else {
      await _notifications.cancelQuestNotifications(_quests[idx]);
    }
    await _saveQuests();
  }

  // ─── Routines ────────────────────────────────────────────────────────────────

  Future<void> addRoutine(HabitRoutine routine) async {
    _routines.add(routine);
    notifyListeners();
    await _storage.saveRoutines(_routines);
  }

  Future<void> updateRoutine(HabitRoutine routine) async {
    final idx = _routines.indexWhere((r) => r.id == routine.id);
    if (idx == -1) return;
    _routines[idx] = routine;
    notifyListeners();
    await _storage.saveRoutines(_routines);
  }

  Future<void> deleteRoutine(String routineId) async {
    _routines.removeWhere((r) => r.id == routineId);
    // Unlink quests from this routine
    _quests = _quests
        .map((q) =>
            q.routineId == routineId ? q.copyWith(clearRoutineId: true) : q)
        .toList();
    notifyListeners();
    await _storage.saveRoutines(_routines);
    await _saveQuests();
  }

  // ─── Achievements ────────────────────────────────────────────────────────────

  Future<void> markAchievementSeen(String achievementId) async {
    final idx = _achievements.indexWhere((a) => a.id == achievementId);
    if (idx == -1) return;
    _achievements[idx] = _achievements[idx].copyWith(seen: true);
    notifyListeners();
    await _storage.saveAchievements(_achievements);
  }

  // ─── Penalty check (called on app load) ─────────────────────────────────────

  Future<int> checkMissedQuestsAndApplyPenalty() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_lastPenaltyCheckDate == null) {
      _lastPenaltyCheckDate = today;
      await _storage.saveQuestPenaltyCheckDate(today);
      return 0;
    }

    if (!_lastPenaltyCheckDate!.isBefore(today)) return 0;

    int totalDamage = 0;
    int missedCount = 0;
    final updatedQuests = List<Quest>.from(_quests);

    DateTime checkDate = _lastPenaltyCheckDate!;
    while (checkDate.isBefore(today)) {
      final dayIdx = checkDate.weekday - 1;

      for (int i = 0; i < updatedQuests.length; i++) {
        final quest = updatedQuests[i];
        if (!quest.isEnabled || !quest.days[dayIdx]) continue;

        final wasCompleted =
            quest.isCompletedOn(checkDate) || quest.isPartialOn(checkDate);

        if (!wasCompleted) {
          if (quest.streakFreezes > 0) {
            // Spend a freeze: preserve streak, no HP damage
            updatedQuests[i] = quest.copyWith(
              streakFreezes: quest.streakFreezes - 1,
            );
          } else {
            totalDamage += 10;
            missedCount++;
            // Reset streak
            updatedQuests[i] = quest.copyWith(streakCount: 0);
          }
        }
      }
      checkDate = checkDate.add(const Duration(days: 1));
    }

    _quests = updatedQuests;
    _lastPenaltyCheckDate = today;

    if (totalDamage > 0) {
      await _stats.modifyHp(-totalDamage);
      debugPrint(
          'QuestPresenter: Missed $missedCount quests. Applied $totalDamage damage.');
      await _notifications.showSimpleNotification(
        title: 'Penalty Applied',
        body: 'You missed $missedCount quests. Took $totalDamage damage.',
      );
    }

    notifyListeners();
    await _saveQuests();
    await _storage.saveQuestPenaltyCheckDate(today);
    return totalDamage;
  }

  // ─── Private helpers ─────────────────────────────────────────────────────────

  int _indexById(int id) => _quests.indexWhere((q) => q.id == id);

  Quest? _findQuestById(int id) {
    try {
      return _quests.firstWhere((q) => q.id == id);
    } catch (_) {
      return null;
    }
  }

  static String _dateKey(DateTime date) => date.toIso8601String().split('T')[0];

  static int _byTime(Quest a, Quest b) {
    if (a.hour != b.hour) return a.hour.compareTo(b.hour);
    return a.minute.compareTo(b.minute);
  }

  bool _xpAwardedToday(Quest quest) {
    if (quest.lastXpAwarded == null) return false;
    final now = DateTime.now();
    final awarded = quest.lastXpAwarded!;
    return awarded.year == now.year &&
        awarded.month == now.month &&
        awarded.day == now.day;
  }

  int _calculateCurrentStreak(Quest quest) {
    if (quest.completedDates.isEmpty) return 0;
    final sorted = List<String>.from(quest.completedDates)..sort();
    int streak = 0;
    DateTime check = DateTime.now();
    for (int i = sorted.length - 1; i >= 0; i--) {
      final date = DateTime.tryParse(sorted[i]);
      if (date == null) break;
      final expected = DateTime(check.year, check.month, check.day);
      final actual = DateTime(date.year, date.month, date.day);
      if (actual.isAtSameMomentAs(expected) ||
          actual.isAtSameMomentAs(expected.subtract(const Duration(days: 1)))) {
        streak++;
        check = actual;
      } else {
        break;
      }
    }
    return streak;
  }

  Future<void> _checkMilestones(Quest quest) async {
    for (final milestone in _streakMilestones) {
      if (quest.streakCount < milestone) continue;
      final alreadyUnlocked = _achievements
          .any((a) => a.questId == quest.id && a.streakMilestone == milestone);
      if (alreadyUnlocked) continue;

      final achievement = QuestAchievement(
        id: '${quest.id}_$milestone',
        questId: quest.id,
        streakMilestone: milestone,
        unlockedAt: DateTime.now(),
        seen: false,
      );
      _achievements.add(achievement);

      // Award streak freeze at 7 and 30-day milestones (cap at 3)
      if (milestone == 7 || milestone == 30) {
        final idx = _indexById(quest.id);
        if (idx != -1) {
          final current = _quests[idx];
          final newFreezes = (current.streakFreezes + 1).clamp(0, _maxFreezes);
          _quests[idx] = current.copyWith(streakFreezes: newFreezes);
        }
      }
    }
  }

  Future<void> _rescheduleAll() async {
    for (final quest in _quests) {
      if (quest.isEnabled) {
        await _notifications.scheduleQuestNotifications(quest);
      }
    }
  }

  void _scheduleStreakAtRiskIfNeeded() {
    final now = DateTime.now();
    for (final quest in todayOverdueQuests) {
      if (quest.streakCount > 3) {
        _notifications.scheduleStreakAtRiskNotification(
          quest.id,
          quest.title,
          quest.streakCount,
        );
        return; // Only schedule once (first at-risk quest with streak > 3)
      }
    }
  }

  Future<void> _saveQuests() async {
    await _storage.saveQuests(_quests);
  }
}
