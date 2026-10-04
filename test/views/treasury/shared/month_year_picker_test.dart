import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_stepper_pill.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_year_picker.dart';

void main() {
  testWidgets('shows the month label and picks a new month', (tester) async {
    String? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            MonthYearPill(
              monthKey: '2026-06',
              onChanged: (m) => changed = m,
            ),
          ],
        ),
      ),
    ));

    expect(find.text('Jun 2026'), findsOneWidget);

    await tester.tap(find.text('Jun 2026'));
    await tester.pumpAndSettle();

    // The picker sheet exposes a month grid for the selected year.
    expect(find.text('Aug'), findsOneWidget);
    await tester.tap(find.text('Aug'));
    await tester.pumpAndSettle();

    expect(changed, '2026-08');
  });

  testWidgets(
      'MonthStepperPill steps months with chevrons and opens picker on tap',
      (tester) async {
    var currentMonth = '2026-06';
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          return Scaffold(
            body: MonthStepperPill(
              month: currentMonth,
              onMonthChanged: (m) => setState(() => currentMonth = m),
              onTap: () async {
                final picked =
                    await showMonthYearPicker(context, monthKey: currentMonth);
                if (picked != null) setState(() => currentMonth = picked);
              },
            ),
          );
        },
      ),
    ));

    expect(find.byType(MonthStepperPill), findsOneWidget);

    // Chevron forward -> 2026-07
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(currentMonth, '2026-07');

    // Chevron back -> 2026-06
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(currentMonth, '2026-06');

    // Tap label -> opens aggregated month grid picker
    await tester.tap(find.text(monthChipLabel(currentMonth)));
    await tester.pumpAndSettle();

    expect(find.text('Oct'), findsOneWidget);
    await tester.tap(find.text('Oct'));
    await tester.pumpAndSettle();

    expect(currentMonth, '2026-10');
  });
}
