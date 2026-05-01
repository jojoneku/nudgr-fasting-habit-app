import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/presenters/fasting_presenter.dart';
import 'package:intermittent_fasting/models/fasting_log.dart';
import 'package:intermittent_fasting/models/quest.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import '../mocks.mocks.dart';

void main() {
  late MockStorageService mockStorage;
  late MockNotificationService mockNotifications;
  late MockStatsPresenter mockStats;
  late FastingPresenter presenter;

  setUp(() async {
    mockStorage = MockStorageService();
    mockNotifications = MockNotificationService();
    mockStats = MockStatsPresenter();

    // Default storage stubs
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

    // Stats stubs
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

  // ── startFast ───────────────────────────────────────────────────────────────

  group('startFast', () {
    test('sets isFasting to true', () async {
      await presenter.startFast();
      expect(presenter.isFasting, true);
    });

    test('does nothing if already fasting', () async {
      await presenter.startFast();
      final startTime = presenter.startTime;
      await presenter.startFast();
      expect(presenter.startTime, startTime); // unchanged
    });

    test('saves state after starting', () async {
      await presenter.startFast();
      verify(mockStorage.saveState(
        isFasting: true,
        startTime: anyNamed('startTime'),
        eatingStartTime: anyNamed('eatingStartTime'),
        elapsedSeconds: anyNamed('elapsedSeconds'),
        fastingGoalHours: anyNamed('fastingGoalHours'),
        history: anyNamed('history'),
        lastPenaltyCheckDate: anyNamed('lastPenaltyCheckDate'),
      )).called(greaterThanOrEqualTo(1));
    });
  });

  // ── stopFast — success path ─────────────────────────────────────────────────

  group('stopFast — success', () {
    setUp(() async {
      // Start with HP below max so the heal has room to apply.
      // Default initial() has currentHp=100=maxHp, which clamps heal to 0.
      when(mockStats.stats)
          .thenReturn(UserStats.initial().copyWith(currentHp: 50));
      await presenter.startFast();
      // Backdate startTime to simulate 17h fast
      presenter.startTime = DateTime.now().subtract(const Duration(hours: 17));
    });

    test('sets isFasting to false', () async {
      await presenter.stopFast();
      expect(presenter.isFasting, false);
    });

    test('awards positive XP on success', () async {
      final (xp, _) = await presenter.stopFast();
      expect(xp, greaterThan(0));
      verify(mockStats.addXp(any)).called(1);
    });

    test('heals HP on success', () async {
      final (_, hp) = await presenter.stopFast();
      expect(hp, greaterThan(0));
      verify(mockStats.modifyHp(any)).called(1);
    });

    test('increments streak on success', () async {
      await presenter.stopFast();
      verify(mockStats.incrementStreak()).called(1);
    });

    test('adds entry to history', () async {
      await presenter.stopFast();
      expect(presenter.history.length, 1);
      expect(presenter.history.first.success, true);
    });

    test('transitions to eating window', () async {
      await presenter.stopFast();
      expect(presenter.eatingStartTime, isNotNull);
    });
  });

  // ── stopFast — failure path ─────────────────────────────────────────────────

  group('stopFast — failure (early stop)', () {
    setUp(() async {
      await presenter.startFast();
      // Only 8h — fails the 16h goal
      presenter.startTime = DateTime.now().subtract(const Duration(hours: 8));
    });

    test('returns negative HP change', () async {
      final (_, hp) = await presenter.stopFast();
      expect(hp, lessThan(0));
    });

    test('resets streak on failure', () async {
      await presenter.stopFast();
      verify(mockStats.resetStreak()).called(1);
    });

    test('logs a failed fast', () async {
      await presenter.stopFast();
      expect(presenter.history.first.success, false);
    });
  });
}
