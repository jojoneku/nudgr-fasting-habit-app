import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/views/hub_screen.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/models/fasting_log.dart';
import 'package:intermittent_fasting/models/quest.dart';
import 'package:intermittent_fasting/presenters/hub_presenter.dart';
import '../mocks.mocks.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late MockFastingPresenter mockFasting;
  late MockStatsPresenter mockStats;
  late MockQuestPresenter mockQuest;
  late MockHubPresenter mockHub;
  late MockSettingsPresenter mockSettings;

  setUp(() {
    mockFasting = MockFastingPresenter();
    mockStats = MockStatsPresenter();
    mockQuest = MockQuestPresenter();
    mockHub = MockHubPresenter();
    mockSettings = MockSettingsPresenter();

    when(mockFasting.isFasting).thenReturn(false);
    when(mockFasting.history).thenReturn(<FastingLog>[]);

    when(mockQuest.todayActiveQuests).thenReturn(<Quest>[]);
    when(mockQuest.todayOverdueQuests).thenReturn(<Quest>[]);
    when(mockQuest.todayCompletedQuests).thenReturn(<Quest>[]);

    when(mockStats.stats).thenReturn(UserStats.initial());

    when(mockHub.cardOrder).thenReturn(
      HubCardType.values.where((t) => t != HubCardType.stats).toList(),
    );
  });

  HubScreen _buildHub({MockActivityPresenter? activityPresenter}) => HubScreen(
        hubPresenter: mockHub,
        settingsPresenter: mockSettings,
        fastingPresenter: mockFasting,
        statsPresenter: mockStats,
        questPresenter: mockQuest,
        activityPresenter: activityPresenter,
      );

  group('HubScreen — module cards', () {
    testWidgets('renders fasting and quests card titles', (tester) async {
      await tester.pumpWidget(_wrap(_buildHub()));
      await tester.pump();

      expect(find.text('Fasting'), findsOneWidget);
      expect(find.text('Quests'), findsOneWidget);
    });

    testWidgets('null optional presenters render no content', (tester) async {
      await tester.pumpWidget(_wrap(_buildHub(activityPresenter: null)));
      await tester.pump();

      // Locked cards have been replaced with SizedBox.shrink — no lock icons
      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });

    testWidgets('Fasting card shows "End fast" button when fasting', (tester) async {
      when(mockFasting.isFasting).thenReturn(true);

      await tester.pumpWidget(_wrap(_buildHub()));
      await tester.pump();

      expect(find.text('End fast'), findsOneWidget);
    });

    testWidgets('Fasting card shows "Start fast" button when idle', (tester) async {
      await tester.pumpWidget(_wrap(_buildHub()));
      await tester.pump();

      expect(find.text('Start fast'), findsOneWidget);
    });
  });
}
