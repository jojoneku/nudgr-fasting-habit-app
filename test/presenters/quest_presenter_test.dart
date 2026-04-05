import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/habit_routine.dart';
import 'package:intermittent_fasting/models/quest.dart';
import 'package:intermittent_fasting/models/quest_achievement.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/quest_presenter.dart';
import '../mocks.mocks.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Build a Quest with sensible defaults, every day.
Quest _quest({
  int id = 1,
  String title = 'Run',
  int hour = 7,
  int minute = 0,
  bool isEnabled = true,
  bool isOneTime = false,
  List<bool>? days,
  List<String>? completedDates,
  List<String>? partialDates,
  int streakCount = 0,
  int streakFreezes = 0,
  int xpReward = 10,
  LinkedStat? linkedStat,
  String? minimumVersion,
  String? routineId,
}) =>
    Quest(
      id: id,
      title: title,
      hour: hour,
      minute: minute,
      isEnabled: isEnabled,
      isOneTime: isOneTime,
      xpReward: xpReward,
      days: days ?? List.filled(7, true),
      completedDates: completedDates ?? [],
      partialDates: partialDates ?? [],
      streakCount: streakCount,
      streakFreezes: streakFreezes,
      linkedStat: linkedStat,
      minimumVersion: minimumVersion,
      routineId: routineId,
    );

/// Build a presenter with stubs pre-configured.
Future<QuestPresenter> _buildPresenter({
  required MockStorageService storage,
  required MockStatsPresenter stats,
  required MockNotificationService notifications,
  List<Quest>? quests,
  DateTime? penaltyCheckDate,
}) async {
  when(storage.loadQuests())
      .thenAnswer((_) async => quests ?? <Quest>[]);
  when(storage.loadRoutines()).thenAnswer((_) async => <HabitRoutine>[]);
  when(storage.loadAchievements())
      .thenAnswer((_) async => <QuestAchievement>[]);
  when(storage.loadQuestPenaltyCheckDate())
      .thenAnswer((_) async => penaltyCheckDate);
  when(storage.saveQuests(any)).thenAnswer((_) async {});
  when(storage.saveRoutines(any)).thenAnswer((_) async {});
  when(storage.saveAchievements(any)).thenAnswer((_) async {});
  when(storage.saveQuestPenaltyCheckDate(any)).thenAnswer((_) async {});
  when(notifications.init()).thenAnswer((_) async {});
  when(notifications.scheduleQuestNotifications(any))
      .thenAnswer((_) async {});
  when(notifications.cancelQuestNotifications(any))
      .thenAnswer((_) async {});
  when(notifications.scheduleStreakAtRiskNotification(any, any, any))
      .thenAnswer((_) async {});
  when(notifications.showSimpleNotification(
          title: anyNamed('title'), body: anyNamed('body')))
      .thenAnswer((_) async {});

  final presenter = QuestPresenter(
    storage: storage,
    stats: stats,
    notifications: notifications,
  );
  // Wait for async _init to complete
  await Future.delayed(Duration.zero);
  return presenter;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late MockStorageService mockStorage;
  late MockNotificationService mockNotifications;
  late MockStatsPresenter mockStats;

  setUp(() {
    mockStorage = MockStorageService();
    mockNotifications = MockNotificationService();
    mockStats = MockStatsPresenter();

    when(mockStats.stats).thenReturn(UserStats.initial());
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.modifyHp(any)).thenAnswer((_) async {});
    when(mockStats.awardStat(any)).thenAnswer((_) async {});
  });

  // ── CRUD ────────────────────────────────────────────────────────────────────

  group('addQuest', () {
    test('Given empty list, When addQuest called, Then quest appears in list',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage, stats: mockStats, notifications: mockNotifications);

      final q = _quest(id: 42, title: 'Meditate');
      await presenter.addQuest(q);

      expect(presenter.quests.length, 1);
      expect(presenter.quests.first.title, 'Meditate');
    });

    test('Given enabled quest, When addQuest called, Then notifications scheduled',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage, stats: mockStats, notifications: mockNotifications);

      await presenter.addQuest(_quest(id: 1));

      verify(mockNotifications.scheduleQuestNotifications(any)).called(1);
    });

    test('Given disabled quest, When addQuest called, Then no notification scheduled',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage, stats: mockStats, notifications: mockNotifications);

      await presenter.addQuest(_quest(id: 1, isEnabled: false));

      verifyNever(mockNotifications.scheduleQuestNotifications(any));
    });
  });

  group('deleteQuest', () {
    test('Given 1 quest, When deleteQuest called, Then list is empty', () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1)]);

      await presenter.deleteQuest(1);

      expect(presenter.quests, isEmpty);
    });

    test('Given quest, When deleteQuest called, Then notifications cancelled',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1)]);

      await presenter.deleteQuest(1);

      verify(mockNotifications.cancelQuestNotifications(any)).called(1);
    });
  });

  group('toggleQuest', () {
    test('Given enabled quest, When toggled off, Then isEnabled is false',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, isEnabled: true)]);

      await presenter.toggleQuest(1, false);

      expect(presenter.quests.first.isEnabled, isFalse);
    });

    test('Given disabled quest, When toggled on, Then notification scheduled',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, isEnabled: false)]);

      await presenter.toggleQuest(1, true);

      verify(mockNotifications.scheduleQuestNotifications(any)).called(1);
    });
  });

  group('updateQuest', () {
    test('Given existing quest, When updateQuest called, Then title is updated',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, title: 'Old Title')]);

      final updated = _quest(id: 1, title: 'New Title');
      await presenter.updateQuest(updated);

      expect(presenter.quests.first.title, 'New Title');
    });
  });

  // ── completeQuest ────────────────────────────────────────────────────────────

  group('completeQuest', () {
    test('Given uncompleted quest, When completed, Then XP is awarded',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, xpReward: 10)]);

      final (xp, _) = await presenter.completeQuest(1);

      expect(xp, greaterThan(0));
      verify(mockStats.addXp(any)).called(1);
    });

    test('Given already completed today, When tapped again, Then completion is toggled off',
        () async {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, completedDates: [today])]);

      final (xp, _) = await presenter.completeQuest(1);

      expect(xp, 0); // undo — no XP
      expect(presenter.quests.first.isCompletedToday, isFalse);
    });

    test('Given full completion, When completed, Then streakCount increments',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, streakCount: 5)]);

      await presenter.completeQuest(1);

      expect(presenter.quests.first.streakCount, 6);
    });

    test('Given partial completion, When completed, Then streak does NOT increment',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, streakCount: 5, minimumVersion: 'At least 5 min')]);

      await presenter.completeQuest(1, type: CompletionType.partial);

      expect(presenter.quests.first.streakCount, 5); // unchanged
    });

    test('Given partial completion, When completed, Then XP is 50% of base',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, xpReward: 20)]);

      // Capture addXp call
      int? capturedXp;
      when(mockStats.addXp(any)).thenAnswer((invocation) async {
        capturedXp = invocation.positionalArguments.first as int;
      });

      await presenter.completeQuest(1, type: CompletionType.partial);

      // Partial = 50% = 10. (No crit possible on partial)
      expect(capturedXp, 10);
    });

    test('Given one-time quest, When completed, Then quest is removed', () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, isOneTime: true)]);

      await presenter.completeQuest(1);

      expect(presenter.quests, isEmpty);
    });

    test('Given quest at 7-day streak milestone, When completed, Then achievement unlocked',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, streakCount: 6)]); // will become 7

      await presenter.completeQuest(1);

      expect(presenter.unseenAchievements.length, 1);
      expect(presenter.unseenAchievements.first.streakMilestone, 7);
    });

    test('Given quest at 7-day milestone, When completed, Then freeze shield awarded',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, streakCount: 6, streakFreezes: 0)]);

      await presenter.completeQuest(1);

      expect(presenter.quests.first.streakFreezes, 1);
    });

    test('Given stat-linked quest at 21 completions, When completed, Then stat auto-incremented',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, linkedStat: LinkedStat.str, streakCount: 20)]);

      await presenter.completeQuest(1); // streak becomes 21

      verify(mockStats.awardStat('str')).called(1);
    });

    test('Given stat-linked quest NOT at threshold, When completed, Then stat NOT auto-incremented',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, linkedStat: LinkedStat.vit, streakCount: 10)]);

      await presenter.completeQuest(1);

      verifyNever(mockStats.awardStat(any));
    });
  });

  // ── streak freeze ────────────────────────────────────────────────────────────

  group('spendStreakFreeze', () {
    test('Given quest with 2 freezes, When freeze spent, Then freezes decrements to 1',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, streakFreezes: 2)]);

      await presenter.spendStreakFreeze(1);

      expect(presenter.quests.first.streakFreezes, 1);
    });

    test('Given quest with 0 freezes, When freeze spent, Then nothing changes',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, streakFreezes: 0)]);

      await presenter.spendStreakFreeze(1);

      expect(presenter.quests.first.streakFreezes, 0);
    });
  });

  // ── checkMissedQuestsAndApplyPenalty ─────────────────────────────────────────

  group('checkMissedQuestsAndApplyPenalty', () {
    test('Given first run, When penalty checked, Then sets date and no damage',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage, stats: mockStats, notifications: mockNotifications);

      final damage = await presenter.checkMissedQuestsAndApplyPenalty();

      expect(damage, 0);
      verifyNever(mockStats.modifyHp(any));
    });

    test('Given quest missed yesterday, When penalty checked, Then HP damage applied',
        () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      // Penalty check processes missed quests during _init
      await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1)], // not completed yesterday
          penaltyCheckDate: yesterday);

      // Damage was applied during init
      verify(mockStats.modifyHp(any)).called(1);
    });

    test('Given missed quest with streak freeze, When penalty checked, Then freeze spent and no HP damage',
        () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      // Quest with 1 freeze, missed yesterday
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, streakFreezes: 1)],
          penaltyCheckDate: yesterday);

      // Freeze spent during init — no HP damage
      verifyNever(mockStats.modifyHp(any));
      expect(presenter.quests.first.streakFreezes, 0);
    });

    test('Given already checked today, When penalty checked again, Then returns 0',
        () async {
      final today = DateTime.now();
      when(mockStorage.loadQuestPenaltyCheckDate())
          .thenAnswer((_) async => today);

      final presenter = await _buildPresenter(
          storage: mockStorage, stats: mockStats, notifications: mockNotifications);

      final damage = await presenter.checkMissedQuestsAndApplyPenalty();

      expect(damage, 0);
    });
  });

  // ── canGraceComplete ─────────────────────────────────────────────────────────

  group('canGraceComplete', () {
    test('Given quest NOT scheduled yesterday, Then canGraceComplete is false',
        () async {
      // Quest only on Monday — if yesterday was a different day this fails
      // Use a safer approach: quest disabled
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, days: List.filled(7, false))]);

      expect(presenter.canGraceComplete(1), isFalse);
    });

    test('Given already completed yesterday, Then canGraceComplete is false',
        () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayKey = yesterday.toIso8601String().split('T')[0];

      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, completedDates: [yesterdayKey])]);

      expect(presenter.canGraceComplete(1), isFalse);
    });
  });

  // ── statProgressFor ──────────────────────────────────────────────────────────

  group('statProgressFor', () {
    test('Given quest with no linkedStat, Then returns 0.0', () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, linkedStat: null)]);

      expect(presenter.statProgressFor(1), 0.0);
    });

    test('Given quest with 7 streak and STR link, Then returns 7/21 ≈ 0.333',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, linkedStat: LinkedStat.str, streakCount: 7)]);

      expect(presenter.statProgressFor(1), closeTo(7 / 21, 0.001));
    });

    test('Given quest with 21 streak (milestone), Then returns 0.0 (resets)',
        () async {
      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [_quest(id: 1, linkedStat: LinkedStat.agi, streakCount: 21)]);

      // 21 % 21 == 0, so progress resets to 0
      expect(presenter.statProgressFor(1), 0.0);
    });
  });

  // ── daily grouping getters ────────────────────────────────────────────────────

  group('daily grouping', () {
    test('Quest scheduled today in future appears in todayActiveQuests',
        () async {
      final now = DateTime.now();
      // Quest 2 hours from now
      final q = _quest(id: 1, hour: (now.hour + 2) % 24, minute: 0);

      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [q]);

      expect(presenter.todayActiveQuests.length, 1);
      expect(presenter.todayOverdueQuests, isEmpty);
    });

    test('Quest scheduled today in past appears in todayOverdueQuests',
        () async {
      final now = DateTime.now();
      if (now.hour == 0) return; // edge case — skip at midnight
      // Quest 1 hour ago
      final q = _quest(id: 1, hour: now.hour - 1, minute: 0);

      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [q]);

      expect(presenter.todayOverdueQuests.length, 1);
      expect(presenter.todayActiveQuests, isEmpty);
    });

    test('Completed quest appears in todayCompletedQuests', () async {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final q = _quest(id: 1, completedDates: [today]);

      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [q]);

      expect(presenter.todayCompletedQuests.length, 1);
      expect(presenter.todayActiveQuests, isEmpty);
      expect(presenter.todayOverdueQuests, isEmpty);
    });

    test('Disabled quest does NOT appear in any daily group', () async {
      final q = _quest(id: 1, isEnabled: false);

      final presenter = await _buildPresenter(
          storage: mockStorage,
          stats: mockStats,
          notifications: mockNotifications,
          quests: [q]);

      expect(presenter.todayActiveQuests, isEmpty);
      expect(presenter.todayOverdueQuests, isEmpty);
      expect(presenter.todayCompletedQuests, isEmpty);
    });
  });

  // ── routines ────────────────────────────────────────────────────────────────

  group('routines', () {
    test('addRoutine appends to routines list', () async {
      final presenter = await _buildPresenter(
          storage: mockStorage, stats: mockStats, notifications: mockNotifications);

      await presenter.addRoutine(HabitRoutine(
        id: 'r1',
        name: 'Morning Ritual',
        icon: 'flash',
        colorHex: '#29B6F6',
        questIds: [],
        scheduledHour: 6,
        scheduledMinute: 0,
      ));

      expect(presenter.routines.length, 1);
      expect(presenter.routines.first.name, 'Morning Ritual');
    });

    test('deleteRoutine removes routine and unlinks its quests', () async {
      when(mockStorage.loadQuests()).thenAnswer((_) async => [
            _quest(id: 1, routineId: 'r1'),
          ]);
      when(mockStorage.loadRoutines()).thenAnswer((_) async => [
            HabitRoutine(
              id: 'r1',
              name: 'Morning',
              icon: 'flash',
              colorHex: '#FF0000',
              questIds: ['1'],
              scheduledHour: 7,
              scheduledMinute: 0,
            ),
          ]);
      when(mockStorage.loadAchievements())
          .thenAnswer((_) async => <QuestAchievement>[]);
      when(mockStorage.loadQuestPenaltyCheckDate()).thenAnswer((_) async => null);
      when(mockStorage.saveQuests(any)).thenAnswer((_) async {});
      when(mockStorage.saveRoutines(any)).thenAnswer((_) async {});
      when(mockStorage.saveAchievements(any)).thenAnswer((_) async {});
      when(mockStorage.saveQuestPenaltyCheckDate(any)).thenAnswer((_) async {});
      when(mockNotifications.init()).thenAnswer((_) async {});
      when(mockNotifications.scheduleQuestNotifications(any))
          .thenAnswer((_) async {});
      when(mockNotifications.cancelQuestNotifications(any))
          .thenAnswer((_) async {});
      when(mockNotifications.scheduleStreakAtRiskNotification(any, any, any))
          .thenAnswer((_) async {});
      when(mockNotifications.showSimpleNotification(
              title: anyNamed('title'), body: anyNamed('body')))
          .thenAnswer((_) async {});

      final presenter = QuestPresenter(
        storage: mockStorage,
        stats: mockStats,
        notifications: mockNotifications,
      );
      await Future.delayed(Duration.zero);

      await presenter.deleteRoutine('r1');

      expect(presenter.routines, isEmpty);
      expect(presenter.quests.first.routineId, isNull);
    });
  });

  // ── achievements ────────────────────────────────────────────────────────────

  group('markAchievementSeen', () {
    test('Given unseen achievement, When marked seen, Then seen is true',
        () async {
      when(mockStorage.loadQuests()).thenAnswer((_) async => <Quest>[]);
      when(mockStorage.loadRoutines()).thenAnswer((_) async => <HabitRoutine>[]);
      when(mockStorage.loadAchievements()).thenAnswer((_) async => [
            QuestAchievement(
              id: '1_7',
              questId: 1,
              streakMilestone: 7,
              unlockedAt: DateTime.now(),
              seen: false,
            )
          ]);
      when(mockStorage.loadQuestPenaltyCheckDate()).thenAnswer((_) async => null);
      when(mockStorage.saveQuests(any)).thenAnswer((_) async {});
      when(mockStorage.saveRoutines(any)).thenAnswer((_) async {});
      when(mockStorage.saveAchievements(any)).thenAnswer((_) async {});
      when(mockStorage.saveQuestPenaltyCheckDate(any)).thenAnswer((_) async {});
      when(mockNotifications.init()).thenAnswer((_) async {});
      when(mockNotifications.scheduleQuestNotifications(any))
          .thenAnswer((_) async {});
      when(mockNotifications.cancelQuestNotifications(any))
          .thenAnswer((_) async {});
      when(mockNotifications.scheduleStreakAtRiskNotification(any, any, any))
          .thenAnswer((_) async {});
      when(mockNotifications.showSimpleNotification(
              title: anyNamed('title'), body: anyNamed('body')))
          .thenAnswer((_) async {});

      final presenter = QuestPresenter(
        storage: mockStorage,
        stats: mockStats,
        notifications: mockNotifications,
      );
      await Future.delayed(Duration.zero);

      await presenter.markAchievementSeen('1_7');

      expect(presenter.unseenAchievements, isEmpty);
      expect(presenter.hasUnseenAchievements, isFalse);
    });
  });
}
