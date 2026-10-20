import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/dev/preview_seed.dart';
import 'package:intermittent_fasting/views/web/pages/ledger/ledger_cells.dart';
import 'package:intermittent_fasting/views/web/pages/ledger/ledger_filters_popover.dart';
import 'package:intermittent_fasting/views/web/pages/ledger/web_ledger_page_v2.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/widgets/web_dialog.dart';
import 'package:intermittent_fasting/views/web/widgets/web_row_menu.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

/// The v2 Ledger page (Plan 063, Phase 4), against the preview seed.
///
/// Pins the canvas contract: Scan a receipt and Add transaction live in the
/// header (no floating button), notes show under the description, every row
/// carries a ⋯ menu with the five actions, the footer prints the presenter's
/// month totals, the Filters & sort popover drives the toolbar chips, the
/// draft row commits on Enter, bulk delete confirms first, and the Add dialog
/// opens on the kit with its installment fold hidden until a credit account
/// is picked. Everything runs in both web themes.
void main() {
  const modes = [true, false];
  String name(bool dark) => dark ? 'dark' : 'light';

  /// A noted credit-card expense dated now, so it sorts to the top of the
  /// grid whatever today's date is. It is the row the menu and notes tests
  /// look at: an outflow on a liability account offers every menu action.
  const keyboardId = 't_test_keyboard';

  Future<LedgerPresenter> seededPresenter(
    WidgetTester tester, {
    bool seed = true,
  }) async {
    final stats = MockStatsPresenter();
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    // Real async: the presenter loads itself from (in-memory) storage and we
    // poll until it is done, which needs real timers.
    final p = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = LocalStorageService();
      await storage.setUserId(seed ? PreviewSeed.userId : 'empty-user');
      if (seed) await PreviewSeed.seedInto(storage);
      final p = LedgerPresenter(storage, stats);
      while (p.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      if (seed) {
        final now = DateTime.now();
        await p.addTransaction(TransactionRecord(
          id: keyboardId,
          date: now,
          accountId: 'a_cc_bpi',
          categoryId: 'c_tech',
          amount: 2450,
          type: TransactionType.outflow,
          description: 'Mechanical keyboard',
          note: 'For the office desk',
          month: toMonthKey(now),
        ));
      }
      return p;
    });
    return p!;
  }

  /// Content widths the shell hands the page: the full 1200 px column at a
  /// wide window, a small desktop, and the column beside the open Nudgy rail.
  const widths = [1440.0, 1100.0, 760.0];

  Future<void> pumpPage(
    WidgetTester tester,
    LedgerPresenter presenter, {
    required bool dark,
    double width = 1440,
    Widget? trailing,
    VoidCallback? onOpenSetup,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: Scaffold(
        body: WebLedgerPageV2(
          presenter: presenter,
          trailing: trailing,
          onOpenSetup: onOpenSetup,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder keyboardRow() => find.byKey(const ValueKey(keyboardId));

  group('WebLedgerPageV2', () {
    for (final dark in modes) {
      for (final width in widths) {
        testWidgets(
            'header: stepper, Scan a receipt and Add transaction in the '
            'toolbar, no floating button at $width px (${name(dark)})',
            (tester) async {
          final p = await seededPresenter(tester);
          await pumpPage(
            tester,
            p,
            dark: dark,
            width: width,
            trailing: const Text('trailing slot'),
          );

          expect(find.text('Ledger'), findsOneWidget);
          expect(find.byKey(WebKeys.ledgerMonthStepper), findsOneWidget);
          expect(find.byKey(WebKeys.ledgerScanReceipt), findsOneWidget);
          expect(find.text('Scan a receipt'), findsOneWidget);
          expect(find.byKey(WebKeys.ledgerAddTransaction), findsOneWidget);
          expect(find.byType(FloatingActionButton), findsNothing);
          expect(find.text('trailing slot'), findsOneWidget);

          // Subtitle carries the month scope and the presenter's totals.
          expect(
            find.textContaining(
              '${monthLabel(p.selectedMonth)} · '
              '${p.ledgerSpreadsheetRows.length} transactions · '
              'In ${formatPeso(p.tableInflow)} · '
              'Out ${formatPeso(p.tableOutflow)}',
            ),
            findsOneWidget,
          );
          expect(find.byKey(WebKeys.ledgerSearch), findsOneWidget);
          expect(find.byKey(WebKeys.ledgerFiltersButton), findsOneWidget);
          expect(find.byKey(WebKeys.ledgerSelectAll), findsOneWidget);
          expect(find.byKey(WebKeys.ledgerDraftRow), findsOneWidget);
          expect(find.byKey(WebKeys.ledgerDraftAdd), findsOneWidget);
          expect(find.byKey(WebKeys.ledgerFooterTotals), findsOneWidget);
          // One ⋯ menu per rendered row.
          expect(find.byKey(WebKeys.ledgerRowMenu), findsWidgets);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets(
          'notes show as a muted subline under the description '
          '(${name(dark)})', (tester) async {
        final p = await seededPresenter(tester);
        await pumpPage(tester, p, dark: dark);

        expect(find.text('Mechanical keyboard'), findsOneWidget);
        final note = find.text('For the office desk');
        expect(note, findsOneWidget);
        final title = tester.getRect(find.text('Mechanical keyboard'));
        final sub = tester.getRect(note);
        expect(sub.top, greaterThan(title.top), reason: 'note sits below');
        final cs = Theme.of(tester.element(note)).colorScheme;
        expect(tester.widget<Text>(note).style?.color, isNot(cs.onSurface));
      });

      testWidgets(
          'the row menu opens and lists the five actions '
          '(${name(dark)})', (tester) async {
        final p = await seededPresenter(tester);
        await pumpPage(tester, p, dark: dark);

        final menu = find.descendant(
          of: keyboardRow(),
          matching: find.byType(WebRowMenu),
        );
        expect(menu, findsOneWidget);
        await tester.tap(menu);
        await tester.pumpAndSettle();

        expect(find.byKey(WebKeys.ledgerRowEdit), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerRowDuplicate), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerRowSplitInstallments), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerRowReimbursable), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerRowDelete), findsOneWidget);
        expect(find.text('Delete · undo for 6 s'), findsOneWidget);

        // Tapping the barrier closes the menu.
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.byKey(WebKeys.ledgerRowEdit), findsNothing);
      });

      testWidgets(
          "footer totals equal the presenter's month in and out "
          '(${name(dark)})', (tester) async {
        final p = await seededPresenter(tester);
        await pumpPage(tester, p, dark: dark);

        final footer = find.byKey(WebKeys.ledgerFooterTotals);
        expect(footer, findsOneWidget);
        expect(
          find.descendant(
            of: footer,
            matching: find.text(formatPeso(p.tableInflow)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: footer,
            matching: find.text(formatPeso(p.tableOutflow)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: footer,
            matching: find.text(
              formatPesoSigned(p.tableInflow - p.tableOutflow),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: footer,
            matching:
                find.textContaining('${monthLabel(p.selectedMonth)} totals'),
          ),
          findsOneWidget,
        );
      });

      testWidgets(
          'Add transaction opens the kit dialog with the segmented '
          'control and no installment fold (${name(dark)})', (tester) async {
        final p = await seededPresenter(tester);
        await pumpPage(tester, p, dark: dark);

        await tester.tap(find.byKey(WebKeys.ledgerAddTransaction));
        await tester.pumpAndSettle();

        // Header button + dialog title + submit.
        expect(find.text('Add transaction'), findsNWidgets(3));
        final segmented = find.byKey(WebKeys.ledgerDialogType);
        expect(segmented, findsOneWidget);
        for (final seg in ['Expense', 'Income', 'Transfer']) {
          expect(
            find.descendant(of: segmented, matching: find.text(seg)),
            findsOneWidget,
            reason: seg,
          );
        }
        expect(find.byKey(WebKeys.ledgerDialogAmount), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerDialogAccount), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerDialogCategory), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerDialogDescription), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerDialogDate), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerDialogMoreOptions), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerDialogSubmit), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerDialogCancel), findsOneWidget);

        // The first account is a bank, so the fold does not appear; the
        // optional fields stay behind "More options" until opened.
        expect(find.byKey(WebKeys.ledgerDialogInstallments), findsNothing);
        expect(find.text('MONTHS'), findsNothing);
        expect(find.byKey(WebKeys.ledgerDialogNotes), findsNothing);

        await tester.tap(find.byKey(WebKeys.ledgerDialogMoreOptions));
        await tester.pumpAndSettle();
        expect(find.byKey(WebKeys.ledgerDialogNotes), findsOneWidget);
        expect(find.byKey(WebKeys.ledgerDialogReimbursable), findsOneWidget);

        await tester.tap(find.byKey(WebKeys.ledgerDialogCancel));
        await tester.pumpAndSettle();
        expect(find.byKey(WebKeys.ledgerDialogType), findsNothing);
      });
    }

    testWidgets('filters popover applies a chip and Clear all removes it',
        (tester) async {
      final p = await seededPresenter(tester);
      await pumpPage(tester, p, dark: true);

      expect(find.text('Outflow only'), findsNothing);
      await tester.tap(find.byKey(WebKeys.ledgerFiltersButton));
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.ledgerFilterAccounts), findsOneWidget);
      expect(find.byKey(WebKeys.ledgerFilterSort), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byKey(WebKeys.ledgerFilterType),
        matching: find.text('Outflow'),
      ));
      await tester.pumpAndSettle();

      final chips = find.byKey(WebKeys.ledgerActiveChips);
      expect(
        find.descendant(of: chips, matching: find.text('Outflow only')),
        findsOneWidget,
      );
      expect(find.byKey(WebKeys.ledgerClearAll), findsOneWidget);
      // The button badge counts the active filter.
      expect(
        find.descendant(
          of: find.byKey(WebKeys.ledgerFiltersButton),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      // Only outflows remain in the grid.
      expect(
        tester.widgetList(find.byType(LedgerAmountCell)).where((w) {
          final cell = w as LedgerAmountCell;
          return cell.enabled && cell.value > 0;
        }),
        isNotEmpty,
      );

      await tester.tap(find.byKey(WebKeys.ledgerFilterClearAll));
      await tester.pumpAndSettle();
      expect(find.text('Outflow only'), findsNothing);
      expect(find.byKey(WebKeys.ledgerClearAll), findsNothing);

      // Done closes the popover.
      await tester.tap(find.byKey(WebKeys.ledgerFilterDone));
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.ledgerFilterDone), findsNothing);
    });

    testWidgets('the × on a chip clears just that filter', (tester) async {
      final p = await seededPresenter(tester);
      await pumpPage(tester, p, dark: false);

      await tester.tap(find.byKey(WebKeys.ledgerFiltersButton));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byKey(WebKeys.ledgerFilterType),
        matching: find.text('Inflow'),
      ));
      await tester.tap(find.byKey(WebKeys.ledgerFilterDone));
      await tester.pumpAndSettle();
      expect(find.text('Inflow only'), findsOneWidget);

      final chip = find.ancestor(
        of: find.text('Inflow only'),
        matching: find.byType(LedgerActiveChip),
      );
      expect(chip, findsOneWidget);
      await tester.tap(
        find.descendant(of: chip, matching: find.byIcon(Icons.close_rounded)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Inflow only'), findsNothing);
    });

    testWidgets('draft row: Enter on the amount adds a row', (tester) async {
      final p = await seededPresenter(tester);
      await pumpPage(tester, p, dark: true);
      final before = p.ledgerSpreadsheetRows.length;

      final draft = find.byKey(WebKeys.ledgerDraftRow);
      await tester.enterText(
        find.descendant(of: draft, matching: find.byType(TextField)).first,
        'Taho',
      );
      await tester.pump();

      // Pick a category through the searchable dropdown: type, then Enter
      // selects the first hit. The popover's search field is an element
      // descendant of the cell (OverlayPortal), so scope the finder to it.
      await tester.tap(find.byKey(WebKeys.ledgerDraftCategory));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(WebKeys.ledgerDraftCategory),
          matching: find.byType(TextField),
        ),
        'Food & Drinks',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(WebKeys.ledgerDraftCategory),
          matching: find.text('Food & Drinks'),
        ),
        findsOneWidget,
        reason: 'the cell now shows the picked category',
      );

      final outflow = find.descendant(
        of: find.byKey(
          ValueKey('${WebKeys.ledgerDraftOutflow.value}_0'),
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(outflow, '35');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(p.ledgerSpreadsheetRows.length, before + 1);
      expect(find.text('Taho'), findsOneWidget);
      expect(find.byKey(WebKeys.ledgerDraftError), findsNothing);
      // The draft reset for the next entry.
      expect(
        find.byKey(ValueKey('${WebKeys.ledgerDraftOutflow.value}_1')),
        findsOneWidget,
      );
    });

    testWidgets('draft row: a missing category shows an inline error, no row',
        (tester) async {
      final p = await seededPresenter(tester);
      await pumpPage(tester, p, dark: false);
      final before = p.ledgerSpreadsheetRows.length;

      final outflow = find.descendant(
        of: find.byKey(ValueKey('${WebKeys.ledgerDraftOutflow.value}_0')),
        matching: find.byType(TextField),
      );
      await tester.enterText(outflow, '35');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(p.ledgerSpreadsheetRows.length, before);
      expect(find.byKey(WebKeys.ledgerDraftError), findsOneWidget);
      expect(
          find.text('Pick a category before adding the row.'), findsOneWidget);
    });

    testWidgets('selecting a row shows the bar; Delete opens the confirm',
        (tester) async {
      final p = await seededPresenter(tester);
      await pumpPage(tester, p, dark: true);

      expect(find.byKey(WebKeys.ledgerSelectionBar), findsNothing);
      await tester.tap(find.descendant(
        of: keyboardRow(),
        matching: find.byType(LedgerCheck),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(WebKeys.ledgerSelectionBar), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(WebKeys.ledgerSelectionChangeCategory), findsOneWidget);

      await tester.tap(find.byKey(WebKeys.ledgerSelectionDelete));
      await tester.pumpAndSettle();
      expect(find.text('Delete 1 transaction?'), findsOneWidget);
      // The confirm's red "Delete 1" (the selection bar has one too).
      expect(
        find.descendant(
          of: find.byType(WebDialog),
          matching: find.widgetWithText(FilledButton, 'Delete 1'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 1 transaction?'), findsNothing);
      expect(keyboardRow(), findsOneWidget);

      await tester.tap(find.byKey(WebKeys.ledgerSelectionClear));
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.ledgerSelectionBar), findsNothing);
    });

    testWidgets('row menu Delete removes the row and offers Undo',
        (tester) async {
      final p = await seededPresenter(tester);
      await pumpPage(tester, p, dark: true);
      final before = p.ledgerSpreadsheetRows.length;

      await tester.tap(find.descendant(
        of: keyboardRow(),
        matching: find.byType(WebRowMenu),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.ledgerRowDelete));
      await tester.pumpAndSettle();

      expect(p.ledgerSpreadsheetRows.length, before - 1);
      expect(keyboardRow(), findsNothing);
      expect(find.text('Deleted "Mechanical keyboard"'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(p.ledgerSpreadsheetRows.length, before);
      expect(keyboardRow(), findsOneWidget);
    });

    testWidgets('a transfer row shows the badge and opens Edit transfer',
        (tester) async {
      final p = await seededPresenter(tester);
      await pumpPage(tester, p, dark: false);

      // The seed dates its transfers early in the month and the grid is a
      // lazy list sorted newest first, so late in the month they sit below
      // the fold and are not built yet. Scroll the grid until one is.
      final badge = find.text('Transfer');
      final grid = find
          .ancestor(of: keyboardRow(), matching: find.byType(Scrollable))
          .first;
      for (var i = 0; i < 50 && badge.evaluate().isEmpty; i++) {
        await tester.drag(grid, const Offset(0, -200));
        await tester.pumpAndSettle();
      }
      expect(badge, findsWidgets);
      await tester.ensureVisible(badge.first);
      await tester.pumpAndSettle();
      await tester.tap(badge.first);
      await tester.pumpAndSettle();

      expect(find.text('Edit transfer'), findsOneWidget);
      expect(find.text('Both sides of the transfer change together.'),
          findsOneWidget);
      expect(find.byKey(WebKeys.ledgerDialogToAccount), findsOneWidget);
      expect(find.byKey(WebKeys.ledgerDialogDelete), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Edit transfer'), findsNothing);
    });

    testWidgets('"Split into installments" opens the dialog with the fold on',
        (tester) async {
      final p = await seededPresenter(tester);
      await pumpPage(tester, p, dark: true);

      await tester.tap(find.descendant(
        of: keyboardRow(),
        matching: find.byType(WebRowMenu),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.ledgerRowSplitInstallments));
      await tester.pumpAndSettle();

      expect(find.byKey(WebKeys.ledgerDialogInstallments), findsOneWidget);
      expect(find.byKey(WebKeys.ledgerDialogInstallmentMonths), findsOneWidget);
      expect(find.byKey(WebKeys.ledgerDialogInstallmentRate), findsOneWidget);
      expect(find.text('Convert to installments'), findsNWidgets(2));
      expect(find.textContaining('/ month'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'search widens the grid to all months and swaps the stepper '
        'for the scope pill', (tester) async {
      final p = await seededPresenter(tester);
      await pumpPage(tester, p, dark: true);

      await tester.enterText(find.byKey(WebKeys.ledgerSearch), 'salary');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byKey(WebKeys.ledgerMonthStepper), findsNothing);
      expect(find.byKey(WebKeys.ledgerScopePill), findsOneWidget);
      // Two salaries: this month's and last month's.
      expect(find.textContaining('All months · 2 matches'), findsOneWidget);
      expect(find.text('Alphaus Salary'), findsNWidgets(2));
    });

    testWidgets('no accounts: the Setup hint with an Open Setup action',
        (tester) async {
      final p = await seededPresenter(tester, seed: false);
      var opened = 0;
      await pumpPage(tester, p, dark: true, onOpenSetup: () => opened++);

      expect(
        find.text('Add an account in Setup before logging transactions.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(WebKeys.ledgerEmptyOpenSetup));
      expect(opened, 1);
      expect(find.byKey(WebKeys.ledgerFooterTotals), findsOneWidget);
    });
  });
}
