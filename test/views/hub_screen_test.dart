import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/views/hub_screen.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/models/fasting_log.dart';
import 'package:intermittent_fasting/models/quest.dart';
import '../mocks.mocks.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late MockFastingPresenter mockFasting;
  late MockStatsPresenter mockStats;

  setUp(() {
    mockFasting = MockFastingPresenter();
    mockStats = MockStatsPresenter();

    // Fasting presenter stubs
    when(mockFasting.isFasting).thenReturn(false);
    when(mockFasting.quests).thenReturn(<Quest>[]);
    when(mockFasting.history).thenReturn(<FastingLog>[]);

    // Stats presenter stubs
    when(mockStats.stats).thenReturn(UserStats.initial());
    when(mockStats.addListener(any)).thenReturn(null);
    when(mockFasting.addListener(any)).thenReturn(null);
  });

  group('HubScreen — module cards', () {
    testWidgets('renders all module card titles', (tester) async {
      await tester.pumpWidget(_wrap(HubScreen(
        fastingPresenter: mockFasting,
        statsPresenter: mockStats,
      )));
      await tester.pump();

      expect(find.text('Fasting'), findsOneWidget);
      expect(find.text('Quests'), findsOneWidget);
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Finance'), findsOneWidget);
    });

    testWidgets('renders RPG names on cards', (tester) async {
      await tester.pumpWidget(_wrap(HubScreen(
        fastingPresenter: mockFasting,
        statsPresenter: mockStats,
      )));
      await tester.pump();

      expect(find.text('DISCIPLINE PROTOCOL'), findsOneWidget);
      expect(find.text('TRAINING GROUNDS'), findsOneWidget);
      expect(find.text('ALCHEMY LAB'), findsOneWidget);
    });

    testWidgets('Activity card is locked when activityPresenter is null',
        (tester) async {
      await tester.pumpWidget(_wrap(HubScreen(
        fastingPresenter: mockFasting,
        statsPresenter: mockStats,
        activityPresenter: null,
      )));
      await tester.pump();

      // Lock icon appears for locked cards (Activity + Finance = 2)
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    });

    testWidgets('Activity card shows subtitle when activityPresenter provided',
        (tester) async {
      final mockActivity = MockActivityPresenter();
      when(mockActivity.hubSubtitle).thenReturn('6,240 / 8,000 steps');

      await tester.pumpWidget(_wrap(HubScreen(
        fastingPresenter: mockFasting,
        statsPresenter: mockStats,
        activityPresenter: mockActivity,
      )));
      await tester.pump();

      expect(find.text('6,240 / 8,000 steps'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(1)); // only Finance
    });

    testWidgets('Fasting card shows "Fasting now" when fasting',
        (tester) async {
      when(mockFasting.isFasting).thenReturn(true);

      await tester.pumpWidget(_wrap(HubScreen(
        fastingPresenter: mockFasting,
        statsPresenter: mockStats,
      )));
      await tester.pump();

      expect(find.text('Fasting now'), findsOneWidget);
    });
  });
}
