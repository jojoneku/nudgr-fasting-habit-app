import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/models/activity_log.dart';
import 'package:intermittent_fasting/models/activity_goals.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/models/weight_entry.dart';
import 'package:intermittent_fasting/models/body_measurement_entry.dart';
import 'package:intermittent_fasting/models/sync_queue_entry.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/food_feedback.dart';
import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/models/grocery/cart_item.dart';
import 'package:intermittent_fasting/models/grocery/saved_trip.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';

void main() {
  late LocalStorageService svc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc = LocalStorageService();
  });

  // ── Activity ────────────────────────────────────────────────────────────────

  group('StorageService — activity', () {
    test('loadTodayActivityLog returns empty log when nothing saved', () async {
      final log = await svc.loadTodayActivityLog();
      expect(log.steps, 0);
    });

    test('saveActivityLog / loadTodayActivityLog round-trip', () async {
      final today = _todayKey();
      final log = ActivityLog(date: today, steps: 5000, isManualEntry: true);
      await svc.saveActivityLog(log);
      final loaded = await svc.loadTodayActivityLog();
      expect(loaded.steps, 5000);
      expect(loaded.isManualEntry, true);
    });

    test('loadActivityHistory excludes today', () async {
      final today = _todayKey();
      final yesterday =
          _dateKey(DateTime.now().subtract(const Duration(days: 1)));
      await svc.saveActivityLog(ActivityLog(date: today, steps: 1000));
      await svc.saveActivityLog(ActivityLog(date: yesterday, steps: 2000));
      final history = await svc.loadActivityHistory();
      expect(history.any((l) => l.date == today), false);
      expect(history.any((l) => l.date == yesterday), true);
    });

    test('loadActivityGoals returns initial when nothing saved', () async {
      final goals = await svc.loadActivityGoals();
      expect(goals.dailyStepGoal, 8000);
    });

    test('saveActivityGoals / loadActivityGoals round-trip', () async {
      await svc.saveActivityGoals(const ActivityGoals(dailyStepGoal: 12000));
      final loaded = await svc.loadActivityGoals();
      expect(loaded.dailyStepGoal, 12000);
    });

    test('saveActivityStreak / loadActivityStreak round-trip', () async {
      await svc.saveActivityStreak(7);
      expect(await svc.loadActivityStreak(), 7);
    });

    test('loadActivityStreak returns 0 when nothing saved', () async {
      expect(await svc.loadActivityStreak(), 0);
    });

    test('saveActivityGoalMetDate / loadActivityGoalMetDate round-trip',
        () async {
      await svc.saveActivityGoalMetDate('2026-03-25');
      expect(await svc.loadActivityGoalMetDate(), '2026-03-25');
    });
  });

  // ── UserStats ────────────────────────────────────────────────────────────────

  group('StorageService — user stats', () {
    test('loadUserStats returns initial when nothing saved', () async {
      final stats = await svc.loadUserStats();
      expect(stats.level, 1);
      expect(stats.currentXp, 0);
    });

    test('saveUserStats / loadUserStats round-trip', () async {
      final stats = UserStats.initial().copyWith(level: 5, currentXp: 200);
      await svc.saveUserStats(stats);
      final loaded = await svc.loadUserStats();
      expect(loaded.level, 5);
      expect(loaded.currentXp, 200);
    });
  });

  // ── Weight / body measurements sync coverage ─────────────────────────────────
  // Regression guard: these were local-only and silently lost on sign-out.
  // They must now mark the userProfile domain dirty so they reach the cloud.

  group('StorageService — weight & body sync', () {
    test('saveWeightLog marks userProfile dirty for sync', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveWeightLog([
        WeightEntry(id: 'w1', weightKg: 72.5, loggedAt: DateTime(2026, 6, 1)),
      ]);
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userProfile),
        true,
      );
    });

    test('saveBodyMeasurements marks userProfile dirty for sync', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveBodyMeasurements([
        BodyMeasurementEntry(
            id: 'b1', loggedAt: DateTime(2026, 6, 1), waistCm: 80),
      ]);
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userProfile),
        true,
      );
    });

    test('weight log round-trips through storage', () async {
      await svc.saveWeightLog([
        WeightEntry(id: 'w1', weightKg: 70, loggedAt: DateTime(2026, 5, 30)),
      ]);
      final loaded = await svc.loadWeightLog();
      expect(loaded.length, 1);
      expect(loaded.first.weightKg, 70);
    });

    test('measurementUnit marks userProfile dirty for sync', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveMeasurementUnit(MeasurementUnit.imperial);
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userProfile),
        true,
      );
    });

    test('notification preferences mark userProfile dirty for sync (Plan 053)',
        () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveNotificationPreferences(NotificationPreferences.defaults());
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userProfile),
        true,
      );
    });

    test('calorie-goal credit ledger marks userProfile dirty for sync',
        () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveCalorieGoalCreditedDates({'2026-06-01'});
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userProfile),
        true,
      );
    });

    test('food feedback marks userCollections dirty for sync', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveFoodFeedback([
        FoodFeedback(
          id: 'f1',
          timestamp: DateTime(2026, 6, 1),
          kind: FoodFeedbackKind.userDislike,
          userQuery: 'rice',
          pickedName: 'White rice',
          estimationSource: 'db',
        ),
      ]);
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userCollections),
        true,
      );
    });
  });

  // ── Grocery (Plan 038) ────────────────────────────────────────────────────────

  group('StorageService — grocery', () {
    RememberedPrice price() => RememberedPrice(
          key: RememberedPrice.keyFor(name: 'milk'),
          displayName: 'Milk',
          lastPrice: 58,
          lastSeen: DateTime(2026, 6, 1),
          timesSeen: 2,
        );

    test('price memory round-trips through storage', () async {
      await svc.saveGroceryPriceMemory([price()]);
      final loaded = await svc.loadGroceryPriceMemory();
      expect(loaded, hasLength(1));
      expect(loaded.first.displayName, 'Milk');
      expect(loaded.first.lastPrice, 58);
    });

    test('saving price memory marks userCollections dirty for sync', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveGroceryPriceMemory([price()]);
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userCollections),
        true,
      );
    });

    test('active cart is local-only (does not mark dirty)', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveGroceryCart([]);
      await svc.saveGroceryBudget(500);
      expect(queue.entries, isEmpty);
    });

    test('trip history round-trips and marks userCollections dirty', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      final trip = SavedTrip(
        id: 't1',
        savedAt: DateTime(2026, 6, 1, 14, 30),
        items: [
          CartItem(
            id: 'i1',
            name: 'Milk',
            quantity: 1,
            unitPrice: 58,
            priceState: PriceState.confirmed,
            addedAt: _epoch,
          ),
        ],
        confirmedTotal: 58,
        estimatedTotal: 0,
        unpricedCount: 0,
      );
      await svc.saveGroceryTripHistory([trip]);

      final loaded = await svc.loadGroceryTripHistory();
      expect(loaded, hasLength(1));
      expect(loaded.first.total, 58);
      expect(loaded.first.items.single.name, 'Milk');
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userCollections),
        true,
      );
    });
  });

  // ── Sign-out is non-destructive (Plan 053) ───────────────────────────────────
  // Regression guard for three rounds of data loss: sign-out must DETACH the
  // user namespace (keep data on disk under `u/$id/`), never wipe it. A stale or
  // empty cloud row can then never destroy local progress.

  group('StorageService — sign-out is non-destructive', () {
    test('detachUser keeps stored data; same user re-login restores it',
        () async {
      await svc.setUserId('user-a');
      await svc.saveUserStats(
          UserStats.initial().copyWith(level: 9, currentXp: 123));

      svc.detachUser(); // sign out

      await svc.setUserId('user-a'); // sign back in
      final loaded = await svc.loadUserStats();
      expect(loaded.level, 9, reason: 'data must survive sign-out');
      expect(loaded.currentXp, 123);
    });

    test('a different account never sees the previous user data', () async {
      await svc.setUserId('user-a');
      await svc.saveUserStats(UserStats.initial().copyWith(level: 9));

      svc.detachUser();

      await svc.setUserId('user-b');
      final loaded = await svc.loadUserStats();
      expect(loaded.level, 1,
          reason: 'key-scoping isolates accounts on a shared device');
    });

    test('clearUserData (explicit reset) DOES wipe — unlike sign-out',
        () async {
      await svc.setUserId('user-a');
      await svc.saveUserStats(UserStats.initial().copyWith(level: 9));

      await svc.clearUserData();

      await svc.setUserId('user-a');
      final loaded = await svc.loadUserStats();
      expect(loaded.level, 1,
          reason: 'explicit reset is destructive by design');
    });
  });
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
