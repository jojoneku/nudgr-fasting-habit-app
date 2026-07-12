import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/fasting_log.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/hub_hero_slots.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/widgets/hub/hub_rings_hero.dart';
import 'package:intermittent_fasting/views/widgets/hub/treasury_hub_card.dart';

import '../mocks.mocks.dart';

/// Renders the redesigned Hub widgets under the app's real dark + light themes
/// and asserts they lay out without exceptions or RenderFlex overflow — the
/// automated equivalent of the both-themes browser-preview check.
void main() {
  Future<void> pumpBothThemes(
    WidgetTester tester,
    Widget child, {
    Size surface = const Size(400, 800),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    for (final theme in [buildDarkTheme(), buildLightTheme()]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  }

  group('HubRingsHero renders in both themes', () {
    testWidgets('fast active + food over-goal + move idle', (tester) async {
      final fasting = MockFastingPresenter();
      final nutrition = MockNutritionPresenter();
      final settings = MockSettingsPresenter();
      when(fasting.isFasting).thenReturn(true);
      when(fasting.elapsedSeconds).thenReturn(8 * 3600);
      when(fasting.targetSeconds).thenReturn(16 * 3600);
      when(fasting.isOvertime).thenReturn(false);
      when(fasting.history).thenReturn(<FastingLog>[]);
      when(nutrition.todayCalories).thenReturn(2312);
      when(nutrition.effectiveGoal).thenReturn(2000);
      when(settings.heroSlots).thenReturn(
          const [HubHeroSlot.fast, HubHeroSlot.food, HubHeroSlot.move]);

      await pumpBothThemes(
        tester,
        HubRingsHero(
            fasting: fasting, nutrition: nutrition, settings: settings),
      );
    });

    testWidgets('macro-split slot + food active', (tester) async {
      final fasting = MockFastingPresenter();
      final nutrition = MockNutritionPresenter();
      final settings = MockSettingsPresenter();
      when(fasting.isFasting).thenReturn(false);
      when(fasting.history).thenReturn(<FastingLog>[]);
      when(nutrition.todayCalories).thenReturn(1200);
      when(nutrition.effectiveGoal).thenReturn(2000);
      when(nutrition.todayProtein).thenReturn(128);
      when(nutrition.todayCarbs).thenReturn(210);
      when(nutrition.todayFat).thenReturn(62);
      when(settings.heroSlots).thenReturn(
          const [HubHeroSlot.macros, HubHeroSlot.food, HubHeroSlot.move]);

      await pumpBothThemes(
        tester,
        HubRingsHero(
            fasting: fasting, nutrition: nutrition, settings: settings),
      );
    });
  });

  group('TreasuryHubCard renders in both themes', () {
    testWidgets('hero + cashflow + bill countdown', (tester) async {
      final treasury = MockTreasuryDashboardPresenter();
      final bills = MockBillsReceivablesPresenter();
      final bill = Bill(
        id: 'b1',
        name: 'Meralco',
        billType: BillType.utility,
        amount: 3200,
        dueDay: 20,
        month: '2026-07',
        categoryId: 'c1',
        accountId: 'a1',
      );
      when(treasury.hasBillImminent).thenReturn(true);
      when(treasury.forecastedNetBalance).thenReturn(19855);
      when(treasury.netWorth).thenReturn(50000);
      when(treasury.monthTotalInflow).thenReturn(68000);
      when(treasury.monthTotalOutflow).thenReturn(41000);
      when(treasury.savingsRate).thenReturn(0.39);
      when(treasury.upcomingBills).thenReturn([bill]);
      when(treasury.isBillOverdue(any)).thenReturn(false);
      when(bills.accounts).thenReturn([
        FinancialAccount(
          id: 'a1',
          name: 'BPI',
          category: AccountCategory.bank,
          balance: 10000,
          colorHex: '#2E7DFF',
          icon: 'bank',
        ),
      ]);

      await pumpBothThemes(
        tester,
        TreasuryHubCard(treasury: treasury, bills: bills, onNavigate: () {}),
      );
    });
  });
}
