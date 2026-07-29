import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/widgets/web_net_worth_hero.dart';
import 'package:intermittent_fasting/views/web/widgets/web_number.dart';
import 'package:intermittent_fasting/views/web/widgets/web_stat_tile.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

import '../../mocks.mocks.dart';

/// Web design-system parity tests — the primitives that carry the mobile Nudgr
/// skin onto desktop (tabular figures, tinted badges, the net-worth hero).
void main() {
  final month = toMonthKey(DateTime.now());
  final prevMonth = previousMonth(month);

  /// True when [finder]'s text is rendered with fixed-advance digits, the
  /// treatment `AppTextStyles.numeric` gives every figure on mobile.
  bool hasTabularFigures(WidgetTester tester, Finder finder) {
    final style = tester.widget<Text>(finder).style;
    return style?.fontFeatures?.contains(const FontFeature.tabularFigures()) ??
        false;
  }

  Widget wrap(Widget child, {required bool dark}) => MaterialApp(
        theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
        home: Scaffold(body: SizedBox(width: 900, child: child)),
      );

  group('WebNumber', () {
    for (final dark in [true, false]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('renders tabular figures in $mode mode', (tester) async {
        await tester.pumpWidget(wrap(const WebNumber('₱1,234.00'), dark: dark));

        expect(find.text('₱1,234.00'), findsOneWidget);
        expect(hasTabularFigures(tester, find.text('₱1,234.00')), isTrue);
      });
    }

    testWidgets('webNumericStyle preserves the base style', (tester) async {
      const base = TextStyle(fontSize: 17, fontWeight: FontWeight.w300);
      final styled = webNumericStyle(base, color: const Color(0xFF00FF00));

      expect(styled?.fontSize, 17);
      expect(styled?.fontWeight, FontWeight.w300);
      expect(styled?.color, const Color(0xFF00FF00));
      expect(
        styled?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  });

  group('WebStatTile', () {
    testWidgets('renders its value with tabular figures', (tester) async {
      await tester.pumpWidget(wrap(
        const WebStatTile(
          label: 'Liquid Cash',
          value: '₱60,500.00',
          sub: 'Spendable across accounts',
          icon: Icons.account_balance_wallet_outlined,
        ),
        dark: true,
      ));

      expect(find.text('LIQUID CASH'), findsOneWidget);
      expect(hasTabularFigures(tester, find.text('₱60,500.00')), isTrue);
    });

    testWidgets('tints the icon badge with the domain accent', (tester) async {
      const accent = Color(0xFFFF8A4C);
      await tester.pumpWidget(wrap(
        const WebStatTile(
          label: 'Upcoming Bills',
          value: '₱2,400.00',
          icon: Icons.receipt_long_outlined,
          iconColor: accent,
        ),
        dark: true,
      ));

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.receipt_long_outlined),
      );
      expect(icon.color, accent);
    });
  });

  group('WebNetWorthHero', () {
    FinancialAccount account(String id, String name, double balance) =>
        FinancialAccount(
          id: id,
          name: name,
          category: AccountCategory.bank,
          balance: balance,
          colorHex: '#2E90FA',
          icon: 'wallet',
        );

    MockStorageService buildStorage({required bool withHistory}) {
      final s = MockStorageService();
      when(s.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(s.loadAccounts()).thenAnswer((_) async => [
            account('a1', 'BPI Personal', 42100),
            account('a2', 'GCash', 18400),
          ]);
      when(s.loadTransactions()).thenAnswer((_) async => <TransactionRecord>[]);
      when(s.loadBills()).thenAnswer((_) async => []);
      when(s.loadReceivables()).thenAnswer((_) async => []);
      when(s.loadBudgets()).thenAnswer((_) async => []);
      when(s.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(s.loadFinanceCategories()).thenAnswer((_) async => []);
      when(s.loadBudgetGroups()).thenAnswer((_) async => []);
      when(s.loadMonthlySummaries()).thenAnswer((_) async => [
            if (withHistory)
              MonthlySummary(
                month: prevMonth,
                totalInflow: 30000,
                totalOutflow: 20000,
                totalBills: 0,
                totalBillsPaid: 0,
                billCount: 0,
                billsPaidCount: 0,
                totalReceivables: 0,
                totalReceived: 0,
                receivableCount: 0,
                netSavings: 10000,
                endingCash: 50000,
                netWorth: 55000,
                accountSnapshots: const {},
                categorySpend: const {},
              ),
          ]);
      when(s.saveMonthlySummaries(any)).thenAnswer((_) async {});
      when(s.saveAccounts(any)).thenAnswer((_) async {});
      return s;
    }

    Future<TreasuryDashboardPresenter> pumpHero(
      WidgetTester tester, {
      required bool withHistory,
      bool dark = true,
    }) async {
      final presenter =
          TreasuryDashboardPresenter(buildStorage(withHistory: withHistory));
      await tester.pumpWidget(
        wrap(WebNetWorthHero(presenter: presenter), dark: dark),
      );
      await tester.pumpAndSettle();
      return presenter;
    }

    for (final dark in [true, false]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('renders figure, momentum and sparkline in $mode mode',
          (tester) async {
        final p = await pumpHero(tester, withHistory: true, dark: dark);

        expect(find.text('NET WORTH'), findsOneWidget);
        expect(find.text(formatPeso(p.netWorth)), findsOneWidget);
        expect(hasTabularFigures(tester, find.text(formatPeso(p.netWorth))),
            isTrue);
        expect(find.byType(AppSparkline), findsOneWidget);
        expect(find.textContaining('%'), findsOneWidget);
      });
    }

    testWidgets('omits the sparkline and pill with sparse history',
        (tester) async {
      final p = await pumpHero(tester, withHistory: false);

      // The figure still renders; only the trend affordances drop away.
      expect(find.text(formatPeso(p.netWorth)), findsOneWidget);
      expect(find.byType(AppSparkline), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('stacks the sparkline below the figure when narrow',
        (tester) async {
      final presenter =
          TreasuryDashboardPresenter(buildStorage(withHistory: true));
      await tester.pumpWidget(MaterialApp(
        theme: buildWebDarkTheme(),
        home: Scaffold(
          // Below WebNetWorthHero's side-by-side threshold.
          body: SizedBox(
            width: 420,
            child: WebNetWorthHero(presenter: presenter),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AppSparkline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
