import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/web/design/web_constants.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/widgets/web_dialog.dart';
import 'package:intermittent_fasting/views/web/widgets/web_list_row.dart';
import 'package:intermittent_fasting/views/web/widgets/web_page_header_v2.dart';
import 'package:intermittent_fasting/views/web/widgets/web_row_menu.dart';
import 'package:intermittent_fasting/views/web/widgets/web_stat_strip.dart';
import 'package:intermittent_fasting/views/web/widgets/web_tabs.dart';

/// The Treasury web v2 shared kit (Plan 063, Phase 2).
///
/// These pin the design-canvas contract every v2 page builds on: the dialog
/// geometry, the field label and error treatment, the input focus ring, tabs
/// that never wrap, an even stat strip that never strands one cell, the row
/// menu and the one confirm style. Everything renders in both web themes.
void main() {
  const modes = [true, false];
  String name(bool dark) => dark ? 'dark' : 'light';

  Future<void> pumpAt(
    WidgetTester tester,
    Widget child, {
    required bool dark,
    double width = 800,
    double height = 700,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: Scaffold(body: child),
    ));
    await tester.pumpAndSettle();
  }

  /// A page with one button that opens [dialog] through [showWebDialog].
  Future<void> openDialog(
    WidgetTester tester,
    WidgetBuilder dialog, {
    required bool dark,
  }) async {
    await pumpAt(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showWebDialog<void>(context, builder: dialog),
          child: const Text('open'),
        ),
      ),
      dark: dark,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('WebDialog', () {
    for (final dark in modes) {
      testWidgets('is 520 wide with radius 24 in ${name(dark)} mode',
          (tester) async {
        await openDialog(
          tester,
          (_) => WebDialog(
            title: 'Add bill',
            subtitle: 'A recurring or one-off payment',
            body: const Text('body'),
            secondary:
                TextButton(onPressed: () {}, child: const Text('Cancel')),
            primary: FilledButton(onPressed: () {}, child: const Text('Add')),
          ),
          dark: dark,
        );

        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        final shape = dialog.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(kWebDialogRadius));
        expect(kWebDialogRadius, 24);

        final surface = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Material),
        );
        expect(tester.getSize(surface.first).width, kWebDialogWidth);
        expect(kWebDialogWidth, 520);

        expect(find.text('Add bill'), findsOneWidget);
        expect(find.text('A recurring or one-off payment'), findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
      });
    }

    testWidgets('footer: primary fills the row without a destructive action',
        (tester) async {
      await openDialog(
        tester,
        (_) => WebDialog(
          title: 't',
          body: const SizedBox(),
          secondary: TextButton(onPressed: () {}, child: const Text('Cancel')),
          primary: FilledButton(onPressed: () {}, child: const Text('Save')),
        ),
        dark: true,
      );
      final primary = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
      expect(primary.height, kWebDialogButtonHeight);
      expect(primary.width, greaterThan(cancel.width * 2));
      expect(primary.left, greaterThan(cancel.right));
    });

    testWidgets('footer: destructive sits far left, primary stays compact',
        (tester) async {
      await openDialog(
        tester,
        (_) => WebDialog(
          title: 't',
          body: const SizedBox(),
          destructive:
              TextButton(onPressed: () {}, child: const Text('Delete')),
          secondary: TextButton(onPressed: () {}, child: const Text('Cancel')),
          primary: FilledButton(onPressed: () {}, child: const Text('Save')),
        ),
        dark: false,
      );
      final del = tester.getRect(find.widgetWithText(TextButton, 'Delete'));
      final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
      final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      expect(del.right, lessThan(cancel.left));
      expect(cancel.right, lessThan(save.left));
      // A compact primary, not the row-filling one.
      expect(save.width, lessThan(200));
    });

    testWidgets('Esc and the close button dismiss it', (tester) async {
      await openDialog(
        tester,
        (_) => WebDialog(
          title: 't',
          body: const SizedBox(),
          primary: FilledButton(onPressed: () {}, child: const Text('Save')),
        ),
        dark: true,
      );
      expect(find.byType(WebDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(WebDialog), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(WebDialog), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(WebDialog), findsNothing);
    });
  });

  group('WebField', () {
    for (final dark in modes) {
      testWidgets('renders the uppercase label and the error in ${name(dark)}',
          (tester) async {
        await pumpAt(
          tester,
          const Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                WebField(
                  label: 'Amount',
                  error: 'Enter an amount',
                  child: WebInput(error: true),
                ),
                WebField(
                  label: 'Notes',
                  optional: true,
                  helper: 'Shown under the description',
                  child: WebInput.multiline(),
                ),
              ],
            ),
          ),
          dark: dark,
        );

        expect(find.text('AMOUNT'), findsOneWidget);
        expect(find.text('Amount'), findsNothing);
        expect(find.text('NOTES'), findsOneWidget);
        expect(find.text('optional'), findsOneWidget);
        expect(find.text('Shown under the description'), findsOneWidget);

        final cs = Theme.of(tester.element(find.text('AMOUNT'))).colorScheme;
        final errorText = tester.widget<Text>(find.text('Enter an amount'));
        expect(errorText.style?.color, cs.error);

        // The input with error:true draws its idle border in the error color.
        final field =
            tester.widget<TextField>(find.byType(TextField).first).decoration!;
        expect(
          (field.enabledBorder! as OutlineInputBorder).borderSide.color,
          cs.error,
        );
      });
    }
  });

  group('WebInput', () {
    for (final dark in modes) {
      testWidgets(
          'is 46 px tall with a 1.5 px primary focus ring in ${name(dark)}',
          (tester) async {
        await pumpAt(
          tester,
          const Padding(padding: EdgeInsets.all(24), child: WebInput()),
          dark: dark,
        );
        expect(tester.getSize(find.byType(TextField)).height, kWebInputHeight);
        expect(kWebInputHeight, 46);

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        final cs = Theme.of(tester.element(find.byType(TextField))).colorScheme;
        final decoration =
            tester.widget<TextField>(find.byType(TextField)).decoration!;
        final focused = decoration.focusedBorder! as OutlineInputBorder;
        expect(focused.borderSide.width, 1.5);
        expect(focused.borderSide.color, cs.primary);
        expect(focused.borderRadius, BorderRadius.circular(12));
        expect(decoration.fillColor, cs.surfaceContainerHigh);
      });
    }

    testWidgets('amount variant is 64 px, 28/800 tabular with a peso prefix',
        (tester) async {
      await pumpAt(
        tester,
        const Padding(padding: EdgeInsets.all(24), child: WebInput.amount()),
        dark: true,
      );
      expect(
          tester.getSize(find.byType(TextField)).height, kWebAmountInputHeight);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style?.fontSize, 28);
      expect(field.style?.fontWeight, FontWeight.w800);
      expect(
        field.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(field.decoration?.prefixText, '₱ ');
      expect(field.keyboardType,
          const TextInputType.numberWithOptions(decimal: true));
    });

    testWidgets('multiline variant starts at three lines', (tester) async {
      await pumpAt(
        tester,
        const Padding(padding: EdgeInsets.all(24), child: WebInput.multiline()),
        dark: false,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.minLines, 3);
      expect(field.maxLines, 6);
      expect(tester.getSize(find.byType(TextField)).height,
          greaterThan(kWebInputHeight));
    });
  });

  group('WebTabs', () {
    const tabs = [
      WebTab('Upcoming', count: 4),
      WebTab('Set-asides', count: 7),
      WebTab('Receivables', count: 2),
      WebTab('Installments', count: 8),
      WebTab('Paid', count: 11),
    ];

    for (final dark in modes) {
      testWidgets('five labels never wrap at 600 px in ${name(dark)}',
          (tester) async {
        var selected = 0;
        await pumpAt(
          tester,
          StatefulBuilder(
            builder: (context, setState) => WebTabs(
              tabs: tabs,
              index: selected,
              onChanged: (i) => setState(() => selected = i),
            ),
          ),
          dark: dark,
          width: 600,
        );

        for (final t in tabs) {
          final text = find.text(t.label);
          expect(text, findsOneWidget);
          expect(tester.widget<Text>(text).softWrap, isFalse);
          // One line: a wrapped label would be at least two lines tall.
          expect(tester.getSize(text).height, lessThan(26));
          expect(find.text('${t.count}'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        // The row scrolls rather than wraps, so the last tab may sit past the
        // right edge until it is scrolled into view.
        await tester.ensureVisible(find.text('Paid'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paid'));
        await tester.pumpAndSettle();
        expect(selected, 4);
      });
    }
  });

  group('WebStatStrip', () {
    final items = [
      for (var i = 0; i < 5; i++)
        WebStat(label: 'Stat $i', value: '₱${i + 1},000.00', caption: 'cap'),
    ];

    test('columnsFor never strands one cell', () {
      expect(WebStatStrip.columnsFor(count: 5, width: 1120), 5);
      expect(WebStatStrip.columnsFor(count: 5, width: 900), 3); // 4 -> 3
      expect(WebStatStrip.columnsFor(count: 5, width: 700), 3);
      expect(WebStatStrip.columnsFor(count: 5, width: 450), 1); // 2 -> 1
      expect(WebStatStrip.columnsFor(count: 4, width: 700), 2); // 3 -> 2
      expect(WebStatStrip.columnsFor(count: 6, width: 700), 3);
      expect(WebStatStrip.columnsFor(count: 3, width: 300), 1);
      expect(WebStatStrip.columnsFor(count: 0, width: 300), 0);
    });

    for (final dark in modes) {
      testWidgets('5 items at 1120 px are 5 equal widths in ${name(dark)}',
          (tester) async {
        await pumpAt(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 1120, child: WebStatStrip(items: items)),
          ),
          dark: dark,
          width: 1200,
        );
        final cells = find.byType(WebStatCell);
        expect(cells, findsNWidgets(5));
        final widths = [
          for (var i = 0; i < 5; i++) tester.getSize(cells.at(i)).width
        ];
        expect(widths.toSet().length, 1, reason: 'all cells equal: $widths');
        final tops = {
          for (var i = 0; i < 5; i++) tester.getRect(cells.at(i)).top
        };
        expect(tops.length, 1, reason: 'one row');
      });
    }

    testWidgets('5 items at 700 px wrap 3 + 2, never 4 + 1', (tester) async {
      await pumpAt(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 700, child: WebStatStrip(items: items)),
        ),
        dark: true,
      );
      final cells = find.byType(WebStatCell);
      final rows = <double, int>{};
      for (var i = 0; i < 5; i++) {
        final top = tester.getRect(cells.at(i)).top;
        rows[top] = (rows[top] ?? 0) + 1;
      }
      expect(rows.values.toList()..sort(), [2, 3]);
      final widths = {
        for (var i = 0; i < 5; i++) tester.getSize(cells.at(i)).width
      };
      expect(widths.length, 1, reason: 'cells on both rows share one width');
    });

    testWidgets('values use tabular figures and the tone color',
        (tester) async {
      await pumpAt(
        tester,
        const WebStatStrip(items: [
          WebStat(label: 'Spent', value: '₱1,200', tone: WebStatTone.danger),
        ]),
        dark: false,
      );
      final value = tester.widget<Text>(find.text('₱1,200'));
      expect(value.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()));
      final cs = Theme.of(tester.element(find.text('Spent'))).colorScheme;
      expect(value.style?.color, cs.error);
    });
  });

  group('WebRowMenu', () {
    for (final dark in modes) {
      testWidgets('opens and fires an item in ${name(dark)}', (tester) async {
        var fired = '';
        await pumpAt(
          tester,
          Center(
            child: WebRowMenu(items: [
              WebMenuItem('Edit',
                  icon: Icons.edit_outlined, onTap: () => fired = 'edit'),
              WebMenuItem('Delete',
                  icon: Icons.delete_outline,
                  destructive: true,
                  onTap: () => fired = 'delete'),
            ]),
          ),
          dark: dark,
        );

        final button = find.byIcon(Icons.more_horiz_rounded);
        expect(button, findsOneWidget);
        final hit = tester.getSize(find.byType(WebRowMenu));
        expect(hit.width, greaterThanOrEqualTo(kWebHitTarget));
        expect(hit.height, greaterThanOrEqualTo(kWebHitTarget));

        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('Edit'), findsOneWidget);
        final cs = Theme.of(tester.element(button)).colorScheme;
        expect(tester.widget<Text>(find.text('Delete')).style?.color, cs.error);

        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(fired, 'delete');
        expect(find.text('Edit'), findsNothing);
      });
    }
  });

  group('showWebConfirm', () {
    Future<List<bool>> openConfirm(WidgetTester tester,
        {required bool dark, bool destructive = true}) async {
      final results = <bool>[];
      await pumpAt(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              results.add(await showWebConfirm(
                context,
                title: 'Delete 2 transactions?',
                message: 'This cannot be undone.',
                confirmLabel: 'Delete 2',
                destructive: destructive,
              ));
            },
            child: const Text('open'),
          ),
        ),
        dark: dark,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    for (final dark in modes) {
      testWidgets('returns true on confirm in ${name(dark)}', (tester) async {
        final results = await openConfirm(tester, dark: dark);
        final confirm = find.widgetWithText(FilledButton, 'Delete 2');
        expect(confirm, findsOneWidget);
        final cs = Theme.of(tester.element(confirm)).colorScheme;
        final style = tester.widget<FilledButton>(confirm).style!;
        expect(style.backgroundColor?.resolve({}), cs.error);

        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(results, [true]);
      });
    }

    testWidgets('returns false on Cancel and on Esc', (tester) async {
      final results = await openConfirm(tester, dark: true);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(results, [false, false]);
    });

    testWidgets('a non-destructive confirm uses the primary fill',
        (tester) async {
      await openConfirm(tester, dark: false, destructive: false);
      final confirm = find.widgetWithText(FilledButton, 'Delete 2');
      expect(tester.widget<FilledButton>(confirm).style, isNull);
    });
  });

  group('WebSegmented', () {
    for (final dark in modes) {
      testWidgets('changes value in ${name(dark)}', (tester) async {
        var value = 'expense';
        await pumpAt(
          tester,
          StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(24),
              child: WebSegmented<String>(
                segments: const [
                  WebSegment('expense', 'Expense',
                      tone: WebSegmentTone.warning),
                  WebSegment('income', 'Income', tone: WebSegmentTone.success),
                  WebSegment('transfer', 'Transfer'),
                ],
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
          dark: dark,
        );

        await tester.tap(find.text('Income'));
        await tester.pumpAndSettle();
        expect(value, 'income');
        await tester.tap(find.text('Transfer'));
        await tester.pumpAndSettle();
        expect(value, 'transfer');

        // Equal-width segments.
        final widths = {
          for (final l in ['Expense', 'Income', 'Transfer'])
            tester
                .getSize(find.ancestor(
                    of: find.text(l), matching: find.byType(InkWell)))
                .width
        };
        expect(widths.length, 1);
      });
    }
  });

  group('WebChips / WebSwitchRow / WebFold / WebMoreOptions', () {
    testWidgets('chips select and the custom chip reflects an off-list value',
        (tester) async {
      int? value = 3;
      var custom = 0;
      await pumpAt(
        tester,
        StatefulBuilder(
          builder: (context, setState) => WebChips<int>(
            options: const [
              WebChipOption(3, '3 mo'),
              WebChipOption(6, '6 mo'),
              WebChipOption(12, '12 mo'),
            ],
            value: value,
            onChanged: (v) => setState(() => value = v),
            allowCustom: true,
            onCustom: () => setState(() {
              custom++;
              value = 7;
            }),
          ),
        ),
        dark: true,
      );
      await tester.tap(find.text('6 mo'));
      await tester.pumpAndSettle();
      expect(value, 6);
      await tester.tap(find.text('Custom…'));
      await tester.pumpAndSettle();
      expect(custom, 1);
      expect(value, 7);
      final cs = Theme.of(tester.element(find.text('Custom…'))).colorScheme;
      expect(
          tester.widget<Text>(find.text('Custom…')).style?.color, cs.primary);
    });

    testWidgets('switch row toggles from anywhere on the row', (tester) async {
      var on = false;
      await pumpAt(
        tester,
        StatefulBuilder(
          builder: (context, setState) => WebSwitchRow(
            title: "I'll get this back",
            subtitle: 'Tracks as money owed to you, not spending',
            value: on,
            onChanged: (v) => setState(() => on = v),
          ),
        ),
        dark: false,
      );
      await tester.tap(find.text("I'll get this back"));
      await tester.pumpAndSettle();
      expect(on, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('fold with a switch shows its body only while on',
        (tester) async {
      var split = false;
      await pumpAt(
        tester,
        StatefulBuilder(
          builder: (context, setState) => WebFold(
            title: 'Split into installments',
            subtitle: 'Bills the card monthly',
            toggle: split,
            onToggle: (v) => setState(() => split = v),
            child: const Text('fold body'),
          ),
        ),
        dark: true,
      );
      expect(find.text('fold body'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(split, isTrue);
      expect(find.text('fold body'), findsOneWidget);
    });

    testWidgets('disclosure fold and More options open on tap', (tester) async {
      await pumpAt(
        tester,
        const Column(
          children: [
            WebFold(title: 'Statement & payment', child: Text('fold body')),
            WebMoreOptions(
              hint: 'notes, reimbursable',
              children: [Text('more a'), Text('more b')],
            ),
          ],
        ),
        dark: false,
      );
      expect(find.text('fold body'), findsNothing);
      expect(find.text('more a'), findsNothing);

      await tester.tap(find.text('Statement & payment'));
      await tester.pumpAndSettle();
      expect(find.text('fold body'), findsOneWidget);

      await tester.tap(find.textContaining('More options'));
      await tester.pumpAndSettle();
      expect(find.text('more a'), findsOneWidget);
      expect(find.text('more b'), findsOneWidget);
    });
  });

  group('WebPageHeaderV2 / WebListRow', () {
    for (final dark in modes) {
      testWidgets(
          'header renders title, subtitle and stepper-first actions in '
          '${name(dark)}', (tester) async {
        await pumpAt(
          tester,
          WebPageHeaderV2(
            title: 'Bills & commitments',
            subtitle: '3 due this week',
            monthStepper: const Text('stepper'),
            actions: [
              FilledButton(onPressed: () {}, child: const Text('Add')),
            ],
          ),
          dark: dark,
        );
        final title = tester.widget<Text>(find.text('Bills & commitments'));
        expect(title.style?.fontSize, 28);
        expect(title.style?.fontWeight, FontWeight.w800);
        expect(find.text('3 due this week'), findsOneWidget);
        final stepper = tester.getRect(find.text('stepper'));
        final add = tester.getRect(find.text('Add'));
        expect(stepper.left, lessThan(add.left));
        expect(add.right, greaterThan(600));
      });
    }

    testWidgets('list row shows tile, title, badge, subtitle and actions',
        (tester) async {
      var tapped = false;
      await pumpAt(
        tester,
        WebListRow(
          leading: const WebRowTile(color: Colors.blue, child: Text('ME')),
          title: 'Meralco',
          subtitle: 'Due Oct 14 · BPI',
          badge: const Text('Due soon'),
          trailing: const Text('₱2,400.00'),
          actions: [
            WebRowMenu(items: [WebMenuItem('Edit', onTap: () {})]),
          ],
          onTap: () => tapped = true,
        ),
        dark: true,
      );
      expect(find.text('ME'), findsOneWidget);
      expect(find.text('Meralco'), findsOneWidget);
      expect(find.text('Due soon'), findsOneWidget);
      expect(find.text('Due Oct 14 · BPI'), findsOneWidget);
      expect(find.text('₱2,400.00'), findsOneWidget);
      expect(tester.getSize(find.byType(WebRowTile)), const Size(36, 36));
      await tester.tap(find.text('Meralco'));
      expect(tapped, isTrue);
    });
  });

  test('kWebDateRange spans 2020 to end of 2035', () {
    expect(kWebDateRange.start, DateTime(2020));
    expect(kWebDateRange.end, DateTime(2035, 12, 31));
  });
}
