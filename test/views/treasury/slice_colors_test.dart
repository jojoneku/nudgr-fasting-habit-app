import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/category_pie_chart_card.dart';
import 'package:intermittent_fasting/views/treasury/history/monthly_summary_detail_view.dart';
import 'package:intermittent_fasting/views/treasury/ledger/transaction_list_tile.dart';
import 'package:intermittent_fasting/views/treasury/shared/category_badge_widget.dart';

/// Plan 071 Phase 3: category and slice colors resolve through
/// `resolveSliceColor` with the theme's brightness on mobile, as on web.

FinanceCategory _cat(String id, String hex) => FinanceCategory(
      id: id,
      name: 'Cat $id',
      type: CategoryType.expense,
      icon: '',
      colorHex: hex,
    );

class _FakeDashboard extends Fake implements TreasuryDashboardPresenter {
  _FakeDashboard(this.slices);
  final List<(FinanceCategory, double)> slices;

  @override
  List<(FinanceCategory, double)> get categorySpendThisMonth => slices;

  @override
  List<(FinanceCategory, double)> get allCategorySpendThisMonth => slices;

  @override
  double get categorySpendThisMonthTotal =>
      slices.fold(0.0, (sum, s) => sum + s.$2);

  @override
  bool get hasMoreCategorySpend => false;
}

MonthlySummary _summary(Map<String, double> categorySpend) => MonthlySummary(
      month: '2026-10',
      totalInflow: 0,
      totalOutflow: 0,
      totalBills: 0,
      totalBillsPaid: 0,
      billCount: 0,
      billsPaidCount: 0,
      totalReceivables: 0,
      totalReceived: 0,
      receivableCount: 0,
      netSavings: 0,
      endingCash: 0,
      accountSnapshots: const {},
      categorySpend: categorySpend,
    );

Future<void> _pump(WidgetTester tester, Widget child, ThemeData theme) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: child),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('resolveSliceColor', () {
    test('light theme deepens the same hex', () {
      const hex = '#5BAAF5';
      final dark = resolveSliceColor(hex, 0);
      final light = resolveSliceColor(hex, 0, brightness: Brightness.light);
      expect(light, isNot(dark));
      expect(light.computeLuminance(), lessThan(dark.computeLuminance()));
    });

    test('an empty hex falls back to the palette by position', () {
      expect(resolveSliceColor('', 0), const Color(0xFFF6685E));
      expect(resolveSliceColor('', 1), const Color(0xFFFF8A4C));
      // A short string must not parse as a near-transparent color.
      expect(resolveSliceColor('#FFF', 2), const Color(0xFFFFCA28));
    });

    test('a 6-digit hex still parses as before', () {
      expect(resolveSliceColor('#7C3AED', 4), const Color(0xFF7C3AED));
      expect(resolveSliceColor('7C3AED', 4), const Color(0xFF7C3AED));
    });
  });

  group('CategoryPieChartCard legend', () {
    Future<Color?> percentColor(WidgetTester tester, ThemeData theme) async {
      final presenter = _FakeDashboard([
        (_cat('a', '#5BAAF5'), 60),
        (_cat('b', '#46BD6B'), 40),
      ]);
      await _pump(
        tester,
        SingleChildScrollView(
          child: CategoryPieChartCard(presenter: presenter),
        ),
        theme,
      );
      return tester.widget<Text>(find.text('60%')).style?.color;
    }

    testWidgets('slice color differs between light and dark for one hex',
        (tester) async {
      final dark = await percentColor(tester, buildDarkTheme());
      final light = await percentColor(tester, buildLightTheme());
      expect(dark, resolveSliceColor('#5BAAF5', 0));
      expect(
          light, resolveSliceColor('#5BAAF5', 0, brightness: Brightness.light));
      expect(light, isNot(dark));
    });
  });

  group('TransactionListTile category color', () {
    Future<Color> badgeColor(WidgetTester tester, ThemeData theme) async {
      await _pump(
        tester,
        TransactionListTile(
          txn: TransactionRecord(
            id: 't1',
            date: DateTime(2026, 10, 3),
            accountId: '',
            categoryId: 'a',
            amount: 120,
            type: TransactionType.outflow,
            description: 'Lunch',
            month: '2026-10',
          ),
          category: _cat('a', '#5BAAF5'),
        ),
        theme,
      );
      return tester.widget<CategoryBadge>(find.byType(CategoryBadge)).color;
    }

    testWidgets('uses the brightness-aware resolved color', (tester) async {
      final dark = await badgeColor(tester, buildDarkTheme());
      final light = await badgeColor(tester, buildLightTheme());
      expect(dark, resolveSliceColor('#5BAAF5', 0));
      expect(
          light, resolveSliceColor('#5BAAF5', 0, brightness: Brightness.light));
    });
  });

  group('History spending by category', () {
    testWidgets('an unknown category gets a palette color by position',
        (tester) async {
      final theme = buildDarkTheme();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: MonthlySummaryDetailView(
          // Both ids are gone from the category list (deleted categories).
          summary: _summary({'gone-1': 300, 'gone-2': 100}),
          categories: const [],
        ),
      ));
      await tester.pump();

      final colors = tester
          .widgetList<CategoryBadge>(find.byType(CategoryBadge))
          .map((b) => b.color)
          .toList();
      // kExpensePalette[0] and [1], fully opaque.
      expect(colors, const [Color(0xFFF6685E), Color(0xFFFF8A4C)]);
      expect(colors, isNot(contains(theme.colorScheme.onSurfaceVariant)));
    });
  });
}
