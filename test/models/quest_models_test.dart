import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/habit_routine.dart';
import 'package:intermittent_fasting/models/quest.dart';
import 'package:intermittent_fasting/models/quest_achievement.dart';

void main() {
  // ── Quest model ──────────────────────────────────────────────────────────────

  group('Quest', () {
    Quest base() => Quest(
          id: 1,
          title: 'Morning Run',
          hour: 7,
          minute: 0,
          days: List.filled(7, true),
        );

    // ── copyWith ──────────────────────────────────────────────────────────────

    group('copyWith', () {
      test('preserves unchanged fields', () {
        final q = base();
        final copy = q.copyWith(title: 'Evening Run');
        expect(copy.id, q.id);
        expect(copy.hour, q.hour);
        expect(copy.days, q.days);
      });

      test('updates specified fields', () {
        final q = base();
        final copy = q.copyWith(title: 'New Title', hour: 18, streakCount: 5);
        expect(copy.title, 'New Title');
        expect(copy.hour, 18);
        expect(copy.streakCount, 5);
      });

      test('clearLinkedStat removes linkedStat', () {
        final q = base().copyWith(linkedStat: LinkedStat.str);
        final copy = q.copyWith(clearLinkedStat: true);
        expect(copy.linkedStat, isNull);
      });

      test('clearReminderMinutes removes reminderMinutes', () {
        final q = base().copyWith(reminderMinutes: 15);
        final copy = q.copyWith(clearReminderMinutes: true);
        expect(copy.reminderMinutes, isNull);
      });

      test('clearRoutineId removes routineId', () {
        final q = base().copyWith(routineId: 'routine-1');
        final copy = q.copyWith(clearRoutineId: true);
        expect(copy.routineId, isNull);
      });
    });

    // ── Serialization ─────────────────────────────────────────────────────────

    group('toJson / fromJson roundtrip', () {
      test('round-trips all base fields', () {
        final q = Quest(
          id: 42,
          title: 'Push-ups',
          hour: 8,
          minute: 30,
          days: [true, false, true, false, true, false, false],
          xpReward: 20,
          isOneTime: true,
          reminderMinutes: 10,
        );
        final restored = Quest.fromJson(q.toJson());
        expect(restored.id, q.id);
        expect(restored.title, q.title);
        expect(restored.hour, q.hour);
        expect(restored.minute, q.minute);
        expect(restored.days, q.days);
        expect(restored.xpReward, q.xpReward);
        expect(restored.isOneTime, q.isOneTime);
        expect(restored.reminderMinutes, q.reminderMinutes);
      });

      test('round-trips new plan-005 fields', () {
        final q = Quest(
          id: 1,
          title: 'Meditate',
          hour: 7,
          minute: 0,
          days: List.filled(7, true),
          linkedStat: LinkedStat.sen,
          anchorNote: 'After coffee',
          minimumVersion: '5 minutes',
          streakCount: 14,
          streakFreezes: 2,
          routineId: 'routine-abc',
        );
        final restored = Quest.fromJson(q.toJson());
        expect(restored.linkedStat, LinkedStat.sen);
        expect(restored.anchorNote, 'After coffee');
        expect(restored.minimumVersion, '5 minutes');
        expect(restored.streakCount, 14);
        expect(restored.streakFreezes, 2);
        expect(restored.routineId, 'routine-abc');
      });

      test('round-trips partialDates', () {
        final q = Quest(
          id: 1,
          title: 'Run',
          hour: 7,
          minute: 0,
          days: List.filled(7, true),
          partialDates: ['2026-04-01', '2026-04-03'],
        );
        final restored = Quest.fromJson(q.toJson());
        expect(restored.partialDates, ['2026-04-01', '2026-04-03']);
      });

      test('migration: legacy lastCompleted field loads into completedDates',
          () {
        final json = {
          'id': 1,
          'title': 'Test',
          'hour': 7,
          'minute': 0,
          'isEnabled': true,
          'days': List.filled(7, true),
          'xpReward': 10,
          'isOneTime': false,
          'lastCompleted': '2026-03-15T08:00:00.000',
        };
        final q = Quest.fromJson(json);
        expect(q.completedDates, contains('2026-03-15'));
      });

      test('migration: missing plan-005 fields default gracefully', () {
        final json = {
          'id': 1,
          'title': 'Legacy Quest',
          'hour': 7,
          'minute': 0,
          'isEnabled': true,
          'days': List.filled(7, true),
          'xpReward': 10,
          'isOneTime': false,
        };
        final q = Quest.fromJson(json);
        expect(q.linkedStat, isNull);
        expect(q.streakCount, 0);
        expect(q.streakFreezes, 0);
        expect(q.routineId, isNull);
        expect(q.partialDates, isEmpty);
      });
    });

    // ── Computed helpers ──────────────────────────────────────────────────────

    group('isCompletedOn / isPartialOn', () {
      test('isCompletedOn returns true for date in completedDates', () {
        final date = DateTime(2026, 4, 1);
        final q = Quest(
          id: 1,
          title: 'Run',
          hour: 7,
          minute: 0,
          days: List.filled(7, true),
          completedDates: ['2026-04-01'],
        );
        expect(q.isCompletedOn(date), isTrue);
      });

      test('isCompletedOn returns false for date not in completedDates', () {
        final q = Quest(
          id: 1,
          title: 'Run',
          hour: 7,
          minute: 0,
          days: List.filled(7, true),
          completedDates: ['2026-04-02'],
        );
        expect(q.isCompletedOn(DateTime(2026, 4, 1)), isFalse);
      });

      test('isPartialOn returns true for date in partialDates', () {
        final date = DateTime(2026, 4, 1);
        final q = Quest(
          id: 1,
          title: 'Run',
          hour: 7,
          minute: 0,
          days: List.filled(7, true),
          partialDates: ['2026-04-01'],
        );
        expect(q.isPartialOn(date), isTrue);
      });
    });

    // ── LinkedStat enum ───────────────────────────────────────────────────────

    group('LinkedStat', () {
      test('all values round-trip through toJson name', () {
        for (final stat in LinkedStat.values) {
          final q = base().copyWith(linkedStat: stat);
          final restored = Quest.fromJson(q.toJson());
          expect(restored.linkedStat, stat);
        }
      });

      test('unknown linkedStat string in JSON defaults to null', () {
        final json = {
          'id': 1,
          'title': 'Test',
          'hour': 7,
          'minute': 0,
          'isEnabled': true,
          'days': List.filled(7, true),
          'xpReward': 10,
          'isOneTime': false,
          'linkedStat': 'UNKNOWN_STAT',
        };
        final q = Quest.fromJson(json);
        expect(q.linkedStat, isNull);
      });
    });
  });

  // ── HabitRoutine model ────────────────────────────────────────────────────────

  group('HabitRoutine', () {
    test('toJson / fromJson roundtrip', () {
      final r = HabitRoutine(
        id: 'routine-1',
        name: 'Morning Ritual',
        icon: 'lightning-bolt',
        colorHex: '#29B6F6',
        questIds: ['1', '2', '3'],
        scheduledHour: 6,
        scheduledMinute: 30,
      );
      final restored = HabitRoutine.fromJson(r.toJson());
      expect(restored.id, r.id);
      expect(restored.name, r.name);
      expect(restored.icon, r.icon);
      expect(restored.colorHex, r.colorHex);
      expect(restored.questIds, r.questIds);
      expect(restored.scheduledHour, r.scheduledHour);
      expect(restored.scheduledMinute, r.scheduledMinute);
    });

    test('fromJson uses defaults for missing optional fields', () {
      final json = {
        'id': 'r1',
        'name': 'Evening',
        'questIds': <String>[],
      };
      final r = HabitRoutine.fromJson(json);
      expect(r.icon, 'lightning-bolt');
      expect(r.colorHex, '#29B6F6');
      expect(r.scheduledHour, 8);
      expect(r.scheduledMinute, 0);
    });

    test('copyWith updates fields correctly', () {
      final r = HabitRoutine(
        id: 'r1',
        name: 'Morning',
        icon: 'sun',
        colorHex: '#FF0000',
        questIds: ['1'],
        scheduledHour: 6,
        scheduledMinute: 0,
      );
      final copy = r.copyWith(name: 'Evening', scheduledHour: 20);
      expect(copy.name, 'Evening');
      expect(copy.scheduledHour, 20);
      expect(copy.id, r.id); // unchanged
    });
  });

  // ── QuestAchievement model ────────────────────────────────────────────────────

  group('QuestAchievement', () {
    test('toJson / fromJson roundtrip', () {
      final a = QuestAchievement(
        id: '1_7',
        questId: 1,
        streakMilestone: 7,
        unlockedAt: DateTime(2026, 4, 1, 12, 0),
        seen: false,
      );
      final restored = QuestAchievement.fromJson(a.toJson());
      expect(restored.id, a.id);
      expect(restored.questId, a.questId);
      expect(restored.streakMilestone, a.streakMilestone);
      expect(restored.unlockedAt, a.unlockedAt);
      expect(restored.seen, a.seen);
    });

    test('defaults seen to false when missing from JSON', () {
      final json = {
        'id': '1_7',
        'questId': 1,
        'streakMilestone': 7,
        'unlockedAt': '2026-04-01T12:00:00.000',
      };
      final a = QuestAchievement.fromJson(json);
      expect(a.seen, isFalse);
    });

    test('copyWith marks as seen', () {
      final a = QuestAchievement(
        id: '1_7',
        questId: 1,
        streakMilestone: 7,
        unlockedAt: DateTime(2026, 4, 1),
      );
      final seen = a.copyWith(seen: true);
      expect(seen.seen, isTrue);
      expect(seen.id, a.id); // unchanged
    });
  });
}
