import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/dev/preview_seed.dart';
import 'package:intermittent_fasting/views/web/pages/history/web_history_page_v2.dart';
import 'package:intermittent_fasting/views/web/pages/history/web_month_detail_dialog_v2.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/widgets/web_widgets.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

/// The v2 History page (Plan 063, Phase 7) against the preview seed: every
/// canvas section is keyed and present at each width in both themes, the
/// table carries one row per summary (plus the live month), the five-stat
/// strip is one even row, the live card and a table row both open the month
/// detail, "Open in Ledger" hands back the month key, and the range control
/// changes how many closed months are shown.
void main() {
  const widths = [1440.0, 1100.0, 760.0];
  const modes = [true, false];
  String mode(bool dark) => dark ? 'dark' : 'light';

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    await storage.setUserId(PreviewSeed.userId);
    await PreviewSeed.seedInto(storage);
  });

  /// Builds the seeded presenter on the real clock.
  Future<TreasuryHistoryPresenter> seeded(WidgetTester tester) async {
    late TreasuryHistoryPresenter history;
    await tester.runAsync(() async {
      history = TreasuryHistoryPresenter(storage);
      await history.load();
    });
    return history;
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required TreasuryHistoryPresenter presenter,
    double width = 1440,
    bool dark = true,
    ValueChanged<String>? onOpenLedgerMonth,
    bool settle = true,
  }) async {
    // Tall enough that nothing needs scrolling into view before a tap.
    tester.view.physicalSize = Size(width, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: Scaffold(
        body: WebHistoryPageV2(
          presenter: presenter,
          onOpenLedgerMonth: onOpenLedgerMonth,
        ),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  /// Every parity key the page attaches with seeded data.
  const parityKeys = <Key>[
    WebKeys.historyRange,
    WebKeys.historyLiveCard,
    WebKeys.historyLiveCardOpen,
    WebKeys.historyStatStrip,
    WebKeys.historyCashFlowTrend,
    WebKeys.historyMonthlyTable,
    WebKeys.historyCumulativeSavings,
    WebKeys.historyEndingCash,
    WebKeys.historySpendingByCategory,
  ];

  Finder monthRows() => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>)
                .value
                .startsWith('web.history.monthRow.'),
      );

  group('parity', () {
    for (final dark in modes) {
      for (final width in widths) {
        testWidgets('header, keys and cards at $width px in ${mode(dark)}',
            (tester) async {
          final history = await seeded(tester);
          await pumpPage(tester, presenter: history, width: width, dark: dark);

          expect(find.text('History'), findsOneWidget);
          for (final key in parityKeys) {
            expect(find.byKey(key), findsOneWidget, reason: '$key');
          }
          expect(find.text('Cash flow trend'), findsOneWidget);
          expect(find.text('Monthly summary'), findsOneWidget);
          expect(find.text('Cumulative savings'), findsOneWidget);
          expect(find.text('Ending cash trend'), findsOneWidget);
          expect(find.text('Spending by category'), findsOneWidget);
          expect(find.text('Still open — these numbers are still moving'),
              findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('monthly table', () {
    testWidgets('carries one row per closed summary plus the live month',
        (tester) async {
      final history = await seeded(tester);
      await pumpPage(tester, presenter: history);

      // "All" shows every summary the presenter holds.
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      final live = history.currentMonthSummary == null ? 0 : 1;
      expect(monthRows(), findsNWidgets(history.summaries.length + live));
      for (final s in history.summaries) {
        expect(find.byKey(WebKeys.historyMonthRow(s.month)), findsOneWidget,
            reason: s.month);
      }
      expect(find.text(monthLabel(history.currentMonthSummary!.month)),
          findsWidgets);
    });

    testWidgets('the range control changes the visible row count',
        (tester) async {
      final history = await seeded(tester);
      await pumpPage(tester, presenter: history);
      final total = history.summaries.length;
      expect(total, greaterThan(3), reason: 'seed has 6 closed months');

      // Default: last 6 closed months + live.
      expect(monthRows(), findsNWidgets(total.clamp(0, 6) + 1));

      await tester.tap(find.text('3 mo'));
      await tester.pumpAndSettle();
      expect(monthRows(), findsNWidgets(3 + 1));

      await tester.tap(find.text('12 mo'));
      await tester.pumpAndSettle();
      expect(monthRows(), findsNWidgets(total.clamp(0, 12) + 1));

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(monthRows(), findsNWidgets(total + 1));
    });
  });

  group('period stats', () {
    testWidgets('renders five equal-width cells in one row at 1120 px',
        (tester) async {
      final history = await seeded(tester);
      await pumpPage(tester, presenter: history, width: 1120);

      final cells = find.descendant(
        of: find.byKey(WebKeys.historyStatStrip),
        matching: find.byType(WebStatCell),
      );
      expect(cells, findsNWidgets(5));
      final widths = [
        for (final e in cells.evaluate())
          tester.getSize(find.byWidget(e.widget)).width
      ];
      for (final w in widths) {
        expect(w, moreOrLessEquals(widths.first, epsilon: 0.5));
      }
      final tops = [
        for (final e in cells.evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy
      ];
      expect(tops.toSet().length, 1, reason: 'one row');

      expect(find.text('Ending cash change'), findsOneWidget);
      expect(find.text('Avg monthly net'), findsOneWidget);
      expect(find.text('Avg savings rate'), findsOneWidget);
      expect(find.text('Avg saved / mo'), findsOneWidget);
      expect(find.text('Best month'), findsOneWidget);
    });
  });

  group('month detail', () {
    testWidgets('opens from the live card', (tester) async {
      final history = await seeded(tester);
      await pumpPage(tester, presenter: history);

      await tester.tap(find.byKey(WebKeys.historyLiveCard));
      await tester.pumpAndSettle();

      expect(find.byKey(WebKeys.historyMonthDetail), findsOneWidget);
      expect(find.byType(WebMonthDetailDialogV2), findsOneWidget);
      final live = history.currentMonthSummary!;
      expect(
        find.text(
            'Still open · ${live.billsPaidCount} of ${live.billCount} bills paid'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(WebKeys.historyMonthDetailClose));
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.historyMonthDetail), findsNothing);
    });

    testWidgets('opens from a table row', (tester) async {
      final history = await seeded(tester);
      await pumpPage(tester, presenter: history);
      final s = history.summaries.first;

      await tester.tap(find.byKey(WebKeys.historyMonthRow(s.month)));
      await tester.pumpAndSettle();

      expect(find.byKey(WebKeys.historyMonthDetail), findsOneWidget);
      expect(
        find.text('Closed · ${s.billsPaidCount} of ${s.billCount} bills paid'),
        findsOneWidget,
      );
      expect(find.text(s.netSavings >= 0 ? 'Net positive' : 'Net negative'),
          findsOneWidget);
      expect(find.text('Ending cash'), findsOneWidget);
      expect(find.text('Set aside to savings'), findsOneWidget);
      expect(find.text('Bills paid'), findsOneWidget);
      expect(find.text('Receivables received'), findsOneWidget);
    });

    testWidgets('"Open in Ledger" fires the callback with the month key',
        (tester) async {
      final history = await seeded(tester);
      final opened = <String>[];
      await pumpPage(tester, presenter: history, onOpenLedgerMonth: opened.add);
      final s = history.summaries.first;

      await tester.tap(find.byKey(WebKeys.historyMonthRow(s.month)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.historyMonthDetailOpenLedger));
      await tester.pumpAndSettle();

      expect(opened, [s.month]);
      expect(find.byKey(WebKeys.historyMonthDetail), findsNothing);
    });

    testWidgets('hides "Open in Ledger" without a callback', (tester) async {
      final history = await seeded(tester);
      await pumpPage(tester, presenter: history);

      await tester.tap(find.byKey(WebKeys.historyLiveCard));
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.historyMonthDetailOpenLedger), findsNothing);
      expect(find.byKey(WebKeys.historyMonthDetailClose), findsOneWidget);
    });
  });

  group('page states', () {
    MockStorageService emptyStorage() {
      final empty = MockStorageService();
      when(empty.loadMonthlySummaries())
          .thenAnswer((_) async => <MonthlySummary>[]);
      when(empty.loadTransactions())
          .thenAnswer((_) async => <TransactionRecord>[]);
      when(empty.loadBills()).thenAnswer((_) async => <Bill>[]);
      when(empty.loadReceivables()).thenAnswer((_) async => <Receivable>[]);
      when(empty.loadAccounts()).thenAnswer((_) async => <FinancialAccount>[]);
      when(empty.loadFinanceCategories())
          .thenAnswer((_) async => <FinanceCategory>[]);
      when(empty.saveMonthlySummaries(any)).thenAnswer((_) async {});
      return empty;
    }

    testWidgets('shows "No history yet" with nothing recorded', (tester) async {
      final history = TreasuryHistoryPresenter(emptyStorage());
      await history.load();
      await pumpPage(tester, presenter: history);

      expect(find.text('No history yet'), findsOneWidget);
      expect(
        find.text('Monthly summaries appear here after each month closes.'),
        findsOneWidget,
      );
      expect(find.byKey(WebKeys.historyLiveCard), findsNothing);
      expect(find.byKey(WebKeys.historyStatStrip), findsNothing);
    });

    testWidgets('shows a spinner while loading', (tester) async {
      final storage = emptyStorage();
      final gate = Completer<List<MonthlySummary>>();
      when(storage.loadMonthlySummaries()).thenAnswer((_) => gate.future);
      final history = TreasuryHistoryPresenter(storage);
      final loading = history.load();
      await pumpPage(tester, presenter: history, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('History'), findsNothing);

      gate.complete(const []);
      await loading;
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No history yet'), findsOneWidget);
    });
  });
}
