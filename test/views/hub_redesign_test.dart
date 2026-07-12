import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/fasting_log.dart';
import 'package:intermittent_fasting/models/quest.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/views/widgets/hub/hub_rings_hero.dart';
import 'package:intermittent_fasting/views/widgets/hub/quests_hub_card.dart';
import 'package:intermittent_fasting/views/widgets/hub/treasury_hub_card.dart';
import 'package:intermittent_fasting/views/widgets/hub/weight_body_hub_card.dart';

import '../mocks.mocks.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Quest _quest({int id = 1, String title = 'Drink water'}) => Quest(
      id: id,
      title: title,
      hour: 8,
      minute: 0,
      days: List<bool>.filled(7, true),
      xpReward: 40,
    );

void main() {
  group('HubRingsHero — graceful degradation', () {
    testWidgets('renders idle rings with null nutrition/activity, no throw',
        (tester) async {
      final fasting = MockFastingPresenter();
      final settings = MockSettingsPresenter();
      when(fasting.isFasting).thenReturn(false);
      when(fasting.history).thenReturn(<FastingLog>[]);
      when(settings.heroSlots).thenReturn(null);

      await tester.pumpWidget(_wrap(
        HubRingsHero(
          fasting: fasting,
          nutrition: null,
          activity: null,
          settings: settings,
        ),
      ));
      await tester.pump();

      // No fast ever started ⇒ non-faster default: macro-split + Food + Move.
      expect(find.text('Macros'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Move'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Quests micro-action', () {
    testWidgets('Mark done completes the surfaced quest in place',
        (tester) async {
      final quests = MockQuestPresenter();
      final q = _quest();
      when(quests.hasUrgentQuest).thenReturn(true);
      when(quests.todayOverdueQuests).thenReturn([q]);
      when(quests.nextUrgentQuest).thenReturn(q);

      var marked = false;
      await tester.pumpWidget(_wrap(QuestsHubCard(
        quests: quests,
        onNavigate: () {},
        onMarkComplete: () => marked = true,
      )));
      await tester.pump();

      expect(find.text('Mark done'), findsOneWidget);
      await tester.tap(find.text('Mark done'));
      expect(marked, isTrue);
    });
  });

  group('Weight micro-action', () {
    testWidgets('inline entry saves via logWeight', (tester) async {
      final n = MockNutritionPresenter();
      when(n.latestWeight).thenReturn(null);
      when(n.latestMeasurement).thenReturn(null);
      when(n.weightDelta).thenReturn(null);
      when(n.estimatedBodyFatPercent).thenReturn(null);

      await tester.pumpWidget(_wrap(WeightBodyHubCard(
        nutrition: n,
        onOpenBody: () {},
      )));
      await tester.pump();

      // Tap the Weight tile (first 'Tap to add') to reveal the inline editor.
      await tester.tap(find.text('Tap to add').first);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '70');
      await tester.tap(find.text('Save'));
      await tester.pump();

      verify(n.logWeight(70.0)).called(1);
    });
  });

  group('Pay-a-bill micro-action', () {
    Bill bill() => Bill(
          id: 'b1',
          name: 'Meralco',
          billType: BillType.utility,
          amount: 3200,
          dueDay: 20,
          month: '2026-07',
          categoryId: 'c1',
          accountId: 'a1',
        );

    FinancialAccount account() => FinancialAccount(
          id: 'a1',
          name: 'BPI',
          category: AccountCategory.bank,
          balance: 10000,
          colorHex: '#2E7DFF',
          icon: 'bank',
        );

    testWidgets('Pay requires confirmation — no silent mutation',
        (tester) async {
      final treasury = MockTreasuryDashboardPresenter();
      final bills = MockBillsReceivablesPresenter();
      final b = bill();
      when(treasury.hasBillImminent).thenReturn(false);
      when(treasury.upcomingBills).thenReturn([b]);
      when(treasury.savingsRate).thenReturn(null);
      when(treasury.isBillOverdue(any)).thenReturn(false);
      when(bills.accounts).thenReturn([account()]);

      await tester.pumpWidget(_wrap(TreasuryHubCard(
        treasury: treasury,
        bills: bills,
        onNavigate: () {},
      )));
      await tester.pump();

      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();

      // Confirm sheet is up, but nothing committed yet.
      expect(find.textContaining('Confirm payment'), findsOneWidget);
      verifyNever(bills.markBillPaid(any,
          paidAmount: anyNamed('paidAmount'),
          accountId: anyNamed('accountId')));

      await tester.tap(find.textContaining('Confirm payment'));
      await tester.pumpAndSettle();

      verify(bills.markBillPaid('b1', paidAmount: 3200.0, accountId: 'a1'))
          .called(1);
    });
  });
}
