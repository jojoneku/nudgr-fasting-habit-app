import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/models/weight_entry.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';
import 'package:intermittent_fasting/services/sync_service.dart';

/// Plan 053 Phase 4 — regression contracts for the three rounds of data loss.
///
/// These lock the storage-level + decision-logic invariants behind the fix so a
/// future change can't silently reopen the hole. The full end-to-end Supabase
/// push/pull scenarios (multi-device empty-overwrite, tombstone pull-reconcile,
/// wipe→pull) need an injectable backend seam to test without a brittle fake —
/// tracked as a Phase 4 follow-up. Everything testable without that seam is
/// asserted here.
void main() {
  late LocalStorageService svc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc = LocalStorageService();
  });

  group('Contract 1 — sign-out never destroys local data (Phase 0)', () {
    test('detach + same-user re-login restores everything', () async {
      await svc.setUserId('u1');
      await svc.saveUserStats(
          UserStats.initial().copyWith(level: 12, currentXp: 999));
      await svc.saveWeightLog([
        WeightEntry(id: 'w1', weightKg: 71, loggedAt: DateTime(2026, 6, 1))
      ]);

      svc.detachUser(); // sign-out is non-destructive

      await svc.setUserId('u1');
      expect((await svc.loadUserStats()).level, 12);
      expect((await svc.loadWeightLog()).length, 1);
    });
  });

  group(
      'Contract 2 — local backup round-trips and never fights the cloud '
      '(Phase 0.5)', () {
    test('export → wipe → import restores all domains', () async {
      await svc.setUserId('u1');
      await svc.saveUserStats(UserStats.initial().copyWith(level: 9));
      await svc.saveWeightLog([
        WeightEntry(id: 'w1', weightKg: 70, loggedAt: DateTime(2026, 6, 1))
      ]);
      await svc.saveActivityStreak(7);
      final snapshot = await svc.exportUserData();

      await svc.clearUserData();
      await svc.setUserId('u1');
      expect(await svc.hasUserData(), false);

      await svc.importUserData(snapshot);
      expect((await svc.loadUserStats()).level, 9);
      expect((await svc.loadWeightLog()).length, 1);
      expect(await svc.loadActivityStreak(), 7);
    });

    test(
        'importUserData does NOT enqueue sync entries — a restored backup '
        'can never re-push stale data or win LWW over a newer cloud row',
        () async {
      await svc.setUserId('u1');
      await svc.saveUserStats(UserStats.initial().copyWith(level: 9));
      final snapshot = await svc.exportUserData();

      final queue = SyncQueue();
      svc.setSyncQueue(queue); // attach AFTER populating
      await svc.importUserData(snapshot);

      expect(queue.entries, isEmpty,
          reason: 'restore is a raw write — no dirty marking');
    });
  });

  group('Contract 3 — empty/default never overwrites populated (Phase 1)', () {
    test('quests:[] is classified empty; a populated payload is not', () {
      // The push guard skips when local is empty AND cloud is populated; the
      // pull guard skips when remote is empty AND local is populated. This is
      // the exact predicate that stops the `user_quests -> []` clobber.
      expect(SyncService.questsDataEmpty({'quests': [], 'achievements': []}),
          true);
      expect(
          SyncService.questsDataEmpty({
            'quests': [
              {'id': 'q1'}
            ]
          }),
          false);
    });

    test('a fresh-but-not-empty profile (leveled up) is NOT classified empty',
        () {
      expect(
          SyncService.profileDataEmpty({
            'userStats': {'level': 7, 'currentXp': 300}
          }),
          false);
    });
  });

  group('Contract 4 — finance deletes are explicit, not inferred (Phase 3.2)',
      () {
    test('a tombstone is recognized; a real record is not', () {
      expect(SyncService.isTombstone({'__deleted': true}), true);
      expect(SyncService.isTombstone({'id': 'x', 'amount': 5}), false);
    });
  });
}
