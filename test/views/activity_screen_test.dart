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
      await tester.pumpAndSettle();

      expect(find.text('4,000'), findsOneWidget);
    });

    testWidgets('displays step goal summary label', (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await tester.pumpAndSettle();

      expect(find.text('4,000 / 8,000 steps'), findsOneWidget);
    });

    testWidgets('shows manual mode when HC unavailable', (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await tester.pumpAndSettle();

      expect(find.text('Manual mode'), findsOneWidget);
      expect(find.text('Enter Steps'), findsOneWidget);
    });

    testWidgets('shows Sync Now when HC connected', (tester) async {
      when(mockHealth.isAvailable()).thenAnswer((_) async => true);
      when(mockHealth.hasPermissions()).thenAnswer((_) async => true);
      when(mockHealth.readTodaySteps()).thenAnswer((_) async => 4000);
      when(mockHealth.readTodayActiveCalories()).thenAnswer((_) async => null);
      when(mockHealth.readTodayDistance()).thenAnswer((_) async => null);

      final connectedPresenter = ActivityPresenter(
        statsPresenter: mockStats,
        healthService: mockHealth,
        storage: mockStorage,
      );
      await Future.delayed(Duration.zero);

      await tester.pumpWidget(_wrap(ActivityScreen(presenter: connectedPresenter)));
      await tester.pumpAndSettle();

      expect(find.text('Sync Now'), findsOneWidget);
    });

    testWidgets('manual entry sheet opens on Enter Steps tap', (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter Steps'));
      await tester.pumpAndSettle();

      expect(find.text("Today's Steps"), findsOneWidget);
    });

    testWidgets('settings icon opens goal sheet', (tester) async {
      await tester.pumpWidget(_wrap(ActivityScreen(presenter: presenter)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Daily Step Goal'), findsOneWidget);
    });

    testWidgets('shows check icon when goal is met', (tester) async {
      when(mockStorage.loadTodayActivityLog())
          .thenAnswer((_) async => ActivityLog(date: today, steps: 8000));

      final goalMetPresenter = ActivityPresenter(
        statsPresenter: mockStats,
        healthService: mockHealth,
        storage: mockStorage,
      );
      // goalMetDate already set so no XP re-award
      when(mockStorage.loadActivityGoalMetDate())
          .thenAnswer((_) async => today);
      await Future.delayed(Duration.zero);

      await tester.pumpWidget(_wrap(ActivityScreen(presenter: goalMetPresenter)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
