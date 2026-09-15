import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/views/widgets/finance/finance_proposal_card.dart';

class FakeHost extends ChangeNotifier implements FinanceProposalHost {
  FakeHost(this._pending);

  PendingFinanceAction? _pending;
  bool? confirmedWithScope;
  int declines = 0;

  @override
  PendingFinanceAction? get pending => _pending;

  @override
  Future<void> confirm({bool applyToFuture = false}) async {
    confirmedWithScope = applyToFuture;
    _pending = null;
    notifyListeners();
  }

  @override
  void decline() {
    declines++;
    _pending = null;
    notifyListeners();
  }
}

PendingFinanceAction action({bool recurring = false}) => PendingFinanceAction(
      call: const AiToolCall(id: 'tu_1', name: 'addSetAside', input: {}),
      title: 'Set aside ₱3,000 for Braces',
      details: const [
        (label: 'Amount', value: '₱3,000'),
        (label: 'Type', value: 'goal'),
      ],
      isRecurring: recurring,
    );

Future<void> pumpCard(WidgetTester tester, FakeHost host,
    {ThemeData? theme}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      body: FinanceProposalCard(host: host, action: host.pending!),
    ),
  ));
}

/// Mirrors what `FinanceActionsExecutor` really does when one turn carries
/// several proposals: confirming the first swaps the second straight in and
/// notifies once, so no frame is ever built without a card on screen.
class SwappingHost extends ChangeNotifier implements FinanceProposalHost {
  SwappingHost(this._pending, this._next);

  PendingFinanceAction? _pending;
  PendingFinanceAction? _next;
  final List<bool> confirmedScopes = [];

  @override
  PendingFinanceAction? get pending => _pending;

  @override
  Future<void> confirm({bool applyToFuture = false}) async {
    confirmedScopes.add(applyToFuture);
    _pending = _next;
    _next = null;
    notifyListeners();
  }

  @override
  void decline() {}
}

PendingFinanceAction secondAction() => PendingFinanceAction(
      call: const AiToolCall(id: 'tu_2', name: 'addBill', input: {}),
      title: 'Add bill: Internet, ₱999',
      details: const [(label: 'Amount', value: '₱999')],
      isRecurring: true,
    );

void main() {
  testWidgets('shows what will happen before anything is written',
      (tester) async {
    final host = FakeHost(action());
    await pumpCard(tester, host);

    expect(find.text('Set aside ₱3,000 for Braces'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('₱3,000'), findsOneWidget);
    // Nothing is committed by rendering.
    expect(host.confirmedWithScope, isNull);
  });

  testWidgets('a one-off proposal offers no recurrence scope', (tester) async {
    final host = FakeHost(action());
    await pumpCard(tester, host);

    // There is no series to spread across, so the choice would be meaningless.
    expect(find.text('Every month ahead'), findsNothing);
  });

  testWidgets('a recurring proposal defaults to this month only',
      (tester) async {
    final host = FakeHost(action(recurring: true));
    await pumpCard(tester, host);

    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Every month ahead'), findsOneWidget);

    await tester.tap(find.text('Add it'));
    await tester.pump();

    // The narrow default is the point: widening writes into months the user
    // is not looking at.
    expect(host.confirmedWithScope, isFalse);
  });

  testWidgets('the user can widen the scope, and it reaches confirm',
      (tester) async {
    final host = FakeHost(action(recurring: true));
    await pumpCard(tester, host);

    await tester.tap(find.text('Every month ahead'));
    await tester.pump();
    await tester.tap(find.text('Add it'));
    await tester.pump();

    expect(host.confirmedWithScope, isTrue);
  });

  testWidgets('declining writes nothing', (tester) async {
    final host = FakeHost(action());
    await pumpCard(tester, host);

    await tester.tap(find.text('Not now'));
    await tester.pump();

    expect(host.declines, 1);
    expect(host.confirmedWithScope, isNull);
  });

  testWidgets('the scope options meet the 44px touch target', (tester) async {
    final host = FakeHost(action(recurring: true));
    await pumpCard(tester, host);

    final size = tester.getSize(find.ancestor(
      of: find.text('Every month ahead'),
      matching: find.byType(InkWell),
    ));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  group('several proposals in a row', () {
    /// Rebuilds off the host with NO key, which is the harsh case: Flutter
    /// reuses the State, so the card itself has to notice the swap.
    Future<void> pumpRun(WidgetTester tester, SwappingHost host) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: host,
              builder: (_, __) {
                final pending = host.pending;
                // The run ends with nothing pending, exactly as the real host
                // does — the harness has to survive that, not assert on it.
                if (pending == null) return const SizedBox.shrink();
                return FinanceProposalCard(host: host, action: pending);
              },
            ),
          ),
        ));

    testWidgets('the next card is answerable without reopening the sheet',
        (tester) async {
      // The bug: "Add it" stayed disabled on every card after the first, and
      // the only way back was to dismiss the sheet and come in again.
      final host = SwappingHost(action(recurring: true), secondAction());
      await pumpRun(tester, host);

      await tester.tap(find.text('Add it'));
      await tester.pump();

      expect(find.text('Add bill: Internet, ₱999'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull,
          reason: 'the second proposal cannot be confirmed');
    });

    testWidgets('a widened scope does not carry onto the next proposal',
        (tester) async {
      // Worse than the dead button: proposal two would have been written
      // across every future month because proposal one was.
      final host = SwappingHost(action(recurring: true), secondAction());
      await pumpRun(tester, host);

      await tester.tap(find.text('Every month ahead'));
      await tester.pump();
      await tester.tap(find.text('Add it'));
      await tester.pump();
      await tester.tap(find.text('Add it'));
      await tester.pump();

      expect(host.confirmedScopes, [true, false]);
    });
  });

  testWidgets('renders in both themes', (tester) async {
    for (final theme in [ThemeData.dark(), ThemeData.light()]) {
      final host = FakeHost(action(recurring: true));
      await pumpCard(tester, host, theme: theme);
      expect(tester.takeException(), isNull);
      expect(find.text('Add it'), findsOneWidget);
    }
  });
}
