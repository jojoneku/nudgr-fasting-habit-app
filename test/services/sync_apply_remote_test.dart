import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/models/sync_queue_entry.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';

/// `applyRemote` suppresses dirty-marking so a pull doesn't re-queue the data it
/// just pulled. That suppression used to be a plain bool field, which could not
/// tell "this write IS the pull" apart from "the user edited something while the
/// pull was in flight" — and since `applyRemote` awaits, a concurrent user edit
/// saw the flag set, was never queued, and was overwritten by the next pull.
/// The suppression is now scoped to the remote-apply call chain's own zone.
void main() {
  const userId = 'test-user-id';

  late LocalStorageService storage;
  late SyncQueue queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    await storage.setUserId(userId);
    queue = SyncQueue();
    await queue.load(userId: userId);
    storage.setSyncQueue(queue);
  });

  test('a write made by the remote apply itself is not queued', () async {
    await storage.applyRemote(() async {
      await storage.saveNutritionStreak(7);
    });

    expect(queue.pendingCount, 0,
        reason: 'pulled data must not be re-queued for push');
  });

  test('a local edit made while a pull is in flight is still queued', () async {
    final holdPullOpen = Completer<void>();
    final pull = storage.applyRemote(() async {
      await storage.saveNutritionStreak(1);
      await holdPullOpen.future; // pull is mid-flight, awaiting more rows
    });

    // The user edits something on another async path while the pull is open.
    await storage.saveNutritionStreak(42);

    holdPullOpen.complete();
    await pull;

    expect(queue.pendingCount, 1,
        reason: 'the concurrent user edit must reach the cloud');
    expect(queue.entries.single.domain, SyncDomain.userProfile);
  });

  test('suppression ends with the block — later writes queue normally',
      () async {
    await storage.applyRemote(() async {
      await storage.saveNutritionStreak(1);
    });
    await storage.saveNutritionStreak(2);

    expect(queue.pendingCount, 1);
  });

  test('a throwing remote apply still restores normal dirty-marking', () async {
    await expectLater(
      storage.applyRemote(() async => throw StateError('bad row')),
      throwsStateError,
    );
    await storage.saveNutritionStreak(3);

    expect(queue.pendingCount, 1);
  });
}
