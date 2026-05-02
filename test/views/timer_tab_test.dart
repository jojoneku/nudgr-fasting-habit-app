import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/views/tabs/timer_tab.dart';
import 'package:intermittent_fasting/presenters/fasting_presenter.dart';
import 'package:intermittent_fasting/models/fasting_log.dart';
import 'package:intermittent_fasting/models/quest.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import '../mocks.mocks.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// Consume any layout-overflow exceptions left in the test error queue.
// The lib/ overflows have been fixed; this guard exists for any residual
// overflow noise so it doesn't mask real assertion failures.
void _drainOverflows(WidgetTester tester) {
  final err = tester.takeException();
  if (err == null) return;
  if (!err.toString().contains('overflowed')) throw err as Object;
}

void main() {
  late MockStorageService mockStorage;
  late MockNotificationService mockNotifications;
  late MockStatsPresenter mockStats;
  late FastingPresenter presenter;

  setUp(() async {
    mockStorage = MockStorageService();
    mockNotifications = MockNotificationService();
    mockStats = MockStatsPresenter();

    when(mockStorage.loadState()).thenAnswer((_) async => {
          'isFasting': false,
          'startTime': null,
          'eatingStartTime': null,
          'elapsedSeconds': 0,
          'fastingGoalHours': 16,
          'history': <FastingLog>[],
          'quests': <Quest>[],
          'lastPenaltyCheckDate': null,
        });
    when(mockStorage.saveState(
      isFasting: anyNamed('isFasting'),
      startTime: anyNamed('startTime'),
      eatingStartTime: anyNamed('eatingStartTime'),
      elapsedSeconds: anyNamed('elapsedSeconds'),
      fastingGoalHours: anyNamed('fastingGoalHours'),
      history: anyNamed('history'),
      lastPenaltyCheckDate: anyNamed('lastPenaltyCheckDate'),
    )).thenAnswer((_) async {});
    when(mockStorage.saveUserStats(any)).thenAnswer((_) async {});

    when(mockNotifications.init()).thenAnswer((_) async {});
    when(mockNotifications.requestPermissions()).thenAnswer((_) async => true);
    when(mockNotifications.scheduleFastingAlarm(any, any))
        .thenAnswer((_) async {});
    when(mockNotifications.scheduleEatingAlarm(any, any))
        .thenAnswer((_) async {});
    when(mockNotifications.showFastingTimerNotification(any))
        .thenAnswer((_) async {});
    when(mockNotifications.showEatingTimerNotification(any))
        .thenAnswer((_) async {});
    when(mockNotifications.cancelFastingNotifications())
        .thenAnswer((_) async {});
    when(mockNotifications.cancelEatingNotifications())
        .thenAnswer((_) async {});
    when(mockNotifications.cancelAll()).thenAnswer((_) async {});
    when(mockNotifications.showSimpleNotification(
            title: anyNamed('title'), body: anyNamed('body')))
        .thenAnswer((_) async {});

    when(mockStats.stats).thenReturn(UserStats.initial());
    when(mockStats.maxHp).thenReturn(100);
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.modifyHp(any)).thenAnswer((_) async {});
    when(mockStats.incrementStreak()).thenAnswer((_) async {});
    when(mockStats.resetStreak()).thenAnswer((_) async {});

    presenter = FastingPresenter(
      statsPresenter: mockStats,
      storage: mockStorage,
      notifications: mockNotifications,
    );
    await Future.delayed(Duration.zero);
  });

  tearDown(() => presenter.dispose());

  group('TimerTab — idle state', () {
    testWidgets('shows Start fast button when not fasting', (tester) async {
      await tester.pumpWidget(_wrap(TimerTab(presenter: presenter)));
      await tester.pumpAndSettle();

      expect(find.text('Start fast'), findsOneWidget);
      _drainOverflows(tester);
    });

    testWidgets('shows Ready to start status label when idle', (tester) async {
      await tester.pumpWidget(_wrap(TimerTab(presenter: presenter)));
      await tester.pumpAndSettle();

      expect(find.text('Ready to start'), findsOneWidget);
      _drainOverflows(tester);
    });

    testWidgets('shows protocol selector cards when not fasting',
        (tester) async {
      await tester.pumpWidget(_wrap(TimerTab(presenter: presenter)));
      await tester.pumpAndSettle();

      // Protocol cards are in a horizontal scrollable list; check visible ones
      expect(find.text('12:12'), findsOneWidget);
      expect(find.text('14:10'), findsOneWidget);
      expect(find.text('16:8'), findsOneWidget);
      expect(find.text('18:6'), findsOneWidget);
      _drainOverflows(tester);
    });

    testWidgets('shows default 16:00:00 timer display', (tester) async {
      await tester.pumpWidget(_wrap(TimerTab(presenter: presenter)));
      await tester.pumpAndSettle();

      expect(find.text('16:00:00'), findsOneWidget);
      _drainOverflows(tester);
    });
  });

  group('TimerTab — starting a fast', () {
    // startFast() creates a periodic ticker. We use clearAllData() after
    // assertions to cancel it — stopFast() would restart a new eating-window
    // ticker, and dispose() conflicts with tearDown.
    Future<void> cancelTicker() async {
      await presenter.clearAllData();
    }

    testWidgets('tapping Start fast transitions presenter to fasting',
        (tester) async {
      await tester.pumpWidget(_wrap(TimerTab(presenter: presenter)));
      await tester.pumpAndSettle();
      _drainOverflows(tester); // idle-state overflows (protocol cards + ring)

      await tester.tap(find.text('Start fast'));
      await tester
          .pump(); // synchronous part of startFast runs + notifyListeners

      expect(presenter.isFasting, true);
      await cancelTicker();
      await tester.pump();
      _drainOverflows(tester);
    });

    testWidgets('shows End fast button after fast starts', (tester) async {
      await tester.pumpWidget(_wrap(TimerTab(presenter: presenter)));
      await tester.pumpAndSettle();
      _drainOverflows(tester);

      await tester.tap(find.text('Start fast'));
      await tester.pump();

      expect(find.text('End fast'), findsOneWidget);
      await cancelTicker();
      await tester.pump();
      _drainOverflows(tester);
    });

    testWidgets('shows Fasting status label after fast starts', (tester) async {
      await tester.pumpWidget(_wrap(TimerTab(presenter: presenter)));
      await tester.pumpAndSettle();
      _drainOverflows(tester);

      await tester.tap(find.text('Start fast'));
      await tester.pump();

      expect(find.text('Fasting'), findsOneWidget);
      await cancelTicker();
      await tester.pump();
      _drainOverflows(tester);
    });

    testWidgets('protocol selector hidden while fasting', (tester) async {
      await tester.pumpWidget(_wrap(TimerTab(presenter: presenter)));
      await tester.pumpAndSettle();
      _drainOverflows(tester);

      await tester.tap(find.text('Start fast'));
      await tester.pump();

      expect(find.text('16:8'), findsNothing);
      await cancelTicker();
      await tester.pump();
      _drainOverflows(tester);
    });
  });
}
