import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_receivables_view.dart';
import 'package:intermittent_fasting/views/treasury/bills/obligation_card.dart';
import '../../../mocks.mocks.dart';

/// The Receivables section's drag-to-rearrange mode: opt in from the header,
/// drag by an explicit handle, and keep the everyday Receive/edit affordances
/// out of the way while dragging.
void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter presenter;
  late InstallmentPresenter installments;
  late String month;

  Receivable receivable(String name, int day) => Receivable(
        id: name,
        name: name,
        receivableType: ReceivableType.salary,
        amount: 500,
        expectedDate: DateTime(2026, 3, day),
        month: month,
        categoryId: '',
      );

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    month = '2026-03';
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    presenter = BillsReceivablesPresenter(storage, ledger, stats);
    installments = InstallmentPresenter(storage, ledger, stats);
  });

  Future<void> pumpView(WidgetTester tester, List<Receivable> seed) async {
    when(storage.loadReceivables()).thenAnswer((_) async => seed);
    await tester.binding.setSurfaceSize(const Size(393, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: BillsReceivablesView(
        presenter: presenter,
        installmentPresenter: installments,
      ),
    ));
    await tester.pumpAndSettle();
    await presenter.setMonth(month);
    await tester.pumpAndSettle();
  }

  /// Names of the receivable cards, top to bottom. Scoped to the cards because
  /// the "Coming up" timeline above the sections lists the same receivables.
  List<String> order(WidgetTester tester) {
    final found = <(String, double)>[];
    for (final name in ['Aya', 'Bea', 'Chacha']) {
      final card = find.descendant(
        of: find.byType(ObligationCard),
        matching: find.text(name),
      );
      if (tester.any(card)) found.add((name, tester.getCenter(card).dy));
    }
    found.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final row in found) row.$1];
  }

  testWidgets('reorder mode is opt-in and swaps the action for a handle',
      (tester) async {
    await pumpView(tester, [
      receivable('Aya', 1),
      receivable('Bea', 2),
      receivable('Chacha', 3),
    ]);

    // Off by default: cards keep Receive, and no handles are on screen.
    expect(find.text('Receive'), findsNWidgets(3));
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);

    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();

    // The handle takes the action button's place, so the row is no longer a tap
    // target for the mark-received sheet mid-drag.
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNWidgets(3));
    expect(find.text('Receive'), findsNothing);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
    expect(find.text('Receive'), findsNWidgets(3));
  });

  testWidgets('a single receivable offers nothing to rearrange',
      (tester) async {
    await pumpView(tester, [receivable('Aya', 1)]);
    expect(find.text('Reorder'), findsNothing);
  });

  testWidgets('dragging a card by its handle rewrites the persisted order',
      (tester) async {
    await pumpView(tester, [
      receivable('Aya', 1),
      receivable('Bea', 2),
      receivable('Chacha', 3),
    ]);
    expect(order(tester), ['Aya', 'Bea', 'Chacha']);

    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();

    // Drag the bottom card up past the other two — grouping by who owes you.
    final handles = find.byIcon(Icons.drag_indicator_rounded);
    final from = tester.getCenter(handles.at(2));
    final to = tester.getCenter(handles.at(0));
    // The handle is an immediate ReorderableDragStartListener — no long press
    // needed, which is the point of having a handle at all.
    final drag = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 20));
    for (var step = 0; step < 6; step++) {
      await drag
          .moveTo(from + (to - from - const Offset(0, 8)) * ((step + 1) / 6));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await drag.up();
    await tester.pumpAndSettle();

    expect(order(tester), ['Chacha', 'Aya', 'Bea']);
    expect(presenter.pendingReceivables.map((r) => r.sortIndex), [0, 1, 2]);
    // Persisted, so the arrangement is still there on the next launch.
    verify(storage.saveReceivables(any)).called(greaterThanOrEqualTo(1));

    // With an arrangement in place, "Auto" is offered to undo it.
    expect(find.text('Auto'), findsOneWidget);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(order(tester), ['Aya', 'Bea', 'Chacha']);
    expect(find.text('Auto'), findsNothing);
  });
}
