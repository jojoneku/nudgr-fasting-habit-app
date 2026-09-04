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

  testWidgets('renders in both themes', (tester) async {
    for (final theme in [ThemeData.dark(), ThemeData.light()]) {
      final host = FakeHost(action(recurring: true));
      await pumpCard(tester, host, theme: theme);
      expect(tester.takeException(), isNull);
      expect(find.text('Add it'), findsOneWidget);
    }
  });
}
