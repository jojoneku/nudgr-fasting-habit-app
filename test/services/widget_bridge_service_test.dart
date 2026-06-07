import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/widget/widget_snapshot.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/services/widget_bridge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetSnapshot mapping', () {
    test('empty() is signed-out with sentinel values', () {
      final data = WidgetSnapshot.empty().toWidgetData();
      expect(data['w_signed_in'], false);
      expect(data['w_is_fasting'], false);
      expect(data['w_food_protein_goal'], -1);
      expect(data['w_next_quest_id'], -1);
    });

    test('toWidgetData exposes every key the native providers read', () {
      final keys = WidgetSnapshot.empty().toWidgetData().keys.toSet();
      expect(
        keys,
        containsAll(<String>[
          'w_signed_in',
          'w_is_fasting',
          'w_fast_start_millis',
          'w_target_millis',
          'w_fast_goal_hours',
          'w_fast_streak',
          'w_fast_phase',
          'w_food_cals',
          'w_food_goal',
          'w_food_protein',
          'w_food_protein_goal',
          'w_expense_month',
          'w_expense_today',
          'w_weight',
          'w_weight_delta',
          'w_quests_done',
          'w_quests_total',
          'w_next_quest',
          'w_next_quest_id',
          'w_has_urgent',
        ]),
      );
    });

    test('carries populated values verbatim', () {
      const snap = WidgetSnapshot(
        signedIn: true,
        isFasting: true,
        fastStartMillis: 1000,
        targetMillis: 2000,
        fastingGoalHours: 16,
        currentStreak: 5,
        fastPhaseLabel: 'Ketone Mode',
        todayCalories: 1200,
        calorieGoal: 2000,
        proteinGrams: 80,
        proteinGoal: 120,
        monthOutflowLabel: '₱5k',
        todayOutflowLabel: '₱300.00',
        latestWeightLabel: '72.0 kg',
        weightDeltaLabel: '-1.0 kg',
        questsDoneToday: 2,
        questsTotalToday: 5,
        nextQuestLabel: 'Drink water',
        nextQuestId: 7,
        hasUrgentQuest: true,
      );
      final d = snap.toWidgetData();
      expect(d['w_signed_in'], true);
      expect(d['w_fast_phase'], 'Ketone Mode');
      expect(d['w_food_cals'], 1200);
      expect(d['w_next_quest_id'], 7);
      expect(d['w_has_urgent'], true);
    });
  });

  group('parseLaunchUri', () {
    test('maps known deep-link hosts to routes', () {
      expect(WidgetBridgeService.parseLaunchUri(Uri.parse('nudgr://fasting')),
          WidgetRoute.fasting);
      expect(WidgetBridgeService.parseLaunchUri(Uri.parse('nudgr://food')),
          WidgetRoute.foodLog);
      expect(WidgetBridgeService.parseLaunchUri(Uri.parse('nudgr://expense')),
          WidgetRoute.expenseAdd);
      expect(WidgetBridgeService.parseLaunchUri(Uri.parse('nudgr://weight')),
          WidgetRoute.weightLog);
      expect(WidgetBridgeService.parseLaunchUri(Uri.parse('nudgr://quests')),
          WidgetRoute.quests);
    });

    test('returns null for action uris, unknown hosts, and null', () {
      // Action uris are handled by onInteractiveAction, not routed.
      expect(WidgetBridgeService.parseLaunchUri(Uri.parse('nudgr://startfast')),
          isNull);
      expect(WidgetBridgeService.parseLaunchUri(Uri.parse('nudgr://nope')),
          isNull);
      expect(WidgetBridgeService.parseLaunchUri(null), isNull);
    });
  });

  group('onInteractiveAction (background safety)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // home_widget calls go through this channel; accept everything.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('home_widget'),
        (call) async => true,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
    });

    test('records a tap-time token without touching RPG state', () async {
      await WidgetBridgeService.onInteractiveAction(
          Uri.parse('nudgr://startfast'));
      final prefs = await SharedPreferences.getInstance();
      final queue =
          prefs.getStringList(StorageService.kWidgetPendingActions) ?? [];
      expect(queue.length, 1);
      expect(queue.first.startsWith('startfast|'), isTrue);
    });

    test('completequest carries the quest id through the queue', () async {
      await WidgetBridgeService.onInteractiveAction(
          Uri.parse('nudgr://completequest?id=7'));
      final prefs = await SharedPreferences.getInstance();
      final queue =
          prefs.getStringList(StorageService.kWidgetPendingActions) ?? [];
      expect(queue.single.startsWith('completequest|'), isTrue);
      expect(queue.single.endsWith('|7'), isTrue);
    });
  });
}
