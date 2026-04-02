import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/views/activity/activity_screen.dart';
import 'package:intermittent_fasting/presenters/activity_presenter.dart';
import 'package:intermittent_fasting/models/activity_log.dart';
import 'package:intermittent_fasting/models/activity_goals.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import '../mocks.mocks.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

/// Pump enough to complete the 300 ms ring animation without using
/// pumpAndSettle, which hangs when an indeterminate CircularProgressIndicator
/// is visible (its animation never settles).
Future<void> _settle(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 500));

void main() {
  late MockStorageService mockStorage;
  late MockHealthService mockHealth;
  late MockStatsPresenter mockStats;
  late ActivityPresenter presenter;

  final today = _todayKey();

  setUp(() async {
    mockStorage = MockStorageService();
    mockHealth = MockHealthService();
    mockStats = MockStatsPresenter();

    when(mockStorage.loadTodayActivityLog())
        .thenAnswer((_) async => ActivityLog(date: today, steps: 4000));
    when(mockStorage.loadActivityGoals())
        .thenAnswer((_) async => const ActivityGoals(dailyStepGoal: 8000));
    when(mockStorage.loadActivityHistory()).thenAnswer((_) async => []);
    when(mockStorage.loadActivityGoalMetDate()).thenAnswer((_) async => null);
    when(mockStorage.loadActivityStreak()).thenAnswer((_) async => 0);
    when(mockStorage.loadPreferredStepsSource()).thenAnswer((_) async => null);
    when(mockStorage.loadTdeeProfile()).thenAnswer((_) async => null);
    when(mockStorage.saveActivityLog(any)).thenAnswer((_) async {});
    when(mockStorage.saveActivityGoalMetDate(any)).thenAnswer((_) async {});
    when(mockStorage.saveActivityStreak(any)).thenAnswer((_) async {});

    when(mockHealth.isAvailable()).thenAnswer((_) async => false);
    when(mockHealth.hasPermissions()).thenAnswer((_) async => false);

    when(mockStats.stats).thenReturn(UserStats.initial());
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.awardStat(any)).thenAnswer((_) async {});

    presenter = ActivityPresenter(
      statsPresenter: mockStats,
      healthService: mockHealth,
      storage: mockStorage,
    );
    await Future.delayed(Duration.zero);
  });

  group('ActivityScreen', () {
    testWidgets('displays today step count', (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await _settle(tester);

      expect(find.text('4,000'), findsOneWidget);
    });

    testWidgets('displays steps-to-goal label', (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await _settle(tester);

      expect(find.text('4,000 steps to goal'), findsOneWidget);
    });

    testWidgets('shows Enter manually when HC unavailable', (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await _settle(tester);

      expect(find.text('Enter manually'), findsOneWidget);
    });

    testWidgets('shows Connect chip when HC not connected', (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await _settle(tester);

      // Not-connected state shows the Connect chip
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('manual entry sheet opens on Enter manually tap',
        (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await _settle(tester);

      await tester.tap(find.text('Enter manually'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text("Today's Steps"), findsOneWidget);
    });

    testWidgets('goal sheet opens on tune icon tap', (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Daily Goals'), findsOneWidget);
    });

    testWidgets('shows trophy icon when goal is met', (tester) async {
      when(mockStorage.loadTodayActivityLog())
          .thenAnswer((_) async => ActivityLog(date: today, steps: 8000));
      when(mockStorage.loadActivityGoalMetDate())
          .thenAnswer((_) async => today);

      // tester.runAsync runs outside FakeAsync so Future.delayed works normally
      late ActivityPresenter goalMetPresenter;
      await tester.runAsync(() async {
        goalMetPresenter = ActivityPresenter(
          statsPresenter: mockStats,
          healthService: mockHealth,
          storage: mockStorage,
        );
        await Future.delayed(Duration.zero);
      });

      await tester
          .pumpWidget(_wrap(ActivityScreen(presenter: goalMetPresenter)));
      await _settle(tester);

      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });
  });
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
