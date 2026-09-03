import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

AiToolCall call(String name, Map<String, Object?> input,
        [String id = 'tu_1']) =>
    AiToolCall(id: id, name: name, input: input);

BudgetedExpense setAside(String id, String name, double amount) =>
    BudgetedExpense(
      id: id,
      name: name,
      budgetedType: SetAsideType.goal,
      month: '2026-09',
      allocatedAmount: amount,
      categoryId: '',
    );

void main() {
  late MockBillsReceivablesPresenter bills;
  late FinanceActionsExecutor executor;

  setUp(() {
    bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn('2026-09');
    when(bills.allBills).thenReturn([]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([]);
    executor = FinanceActionsExecutor(bills: bills);
  });

  group('reads', () {
    test('a match comes back with its id so an edit can name the row',
        () async {
      when(bills.allBudgetedExpenses)
          .thenReturn([setAside('sa_1', 'Braces', 3000)]);

      final result =
          await executor.runRead(call('findSetAsides', {'query': 'brac'}));

      expect(result.ok, isTrue);
      expect(result.summary, contains('id=sa_1'));
      expect(result.summary, contains('Braces'));
    });

    test('no match tells the model not to invent an id', () async {
      final result =
          await executor.runRead(call('findSetAsides', {'query': 'yacht'}));

      expect(result.ok, isTrue);
      expect(result.summary, contains('No set-asides matched'));
      expect(result.summary, contains('Do not guess an id'));
    });

    test('a read never touches a mutator', () async {
      when(bills.allBudgetedExpenses)
          .thenReturn([setAside('sa_1', 'Braces', 3000)]);

      await executor.runRead(call('findSetAsides', {}));

      verifyNever(bills.addBudgetedExpense(any,
          applyToFuture: anyNamed('applyToFuture')));
    });
  });

  group('proposals', () {
    test('proposing parks the action and writes nothing', () async {
      // Not awaited: the future only completes when the user answers.
      unawaited(executor.propose(call(
          'addSetAside', {'name': 'Braces', 'amount': 3000, 'type': 'goal'})));
      await Future<void>.delayed(Duration.zero);

      expect(executor.pending, isNotNull);
      expect(executor.pending!.title, contains('Braces'));
      expect(executor.pending!.title, contains('₱3000'));
      verifyNever(bills.addBudgetedExpense(any,
          applyToFuture: anyNamed('applyToFuture')));
    });

    test('confirming writes through the owning presenter', () async {
      when(bills.addBudgetedExpense(any,
              applyToFuture: anyNamed('applyToFuture')))
          .thenAnswer((_) async {});

      final pending = executor.propose(call(
          'addSetAside', {'name': 'Braces', 'amount': 3000, 'type': 'goal'}));
      await Future<void>.delayed(Duration.zero);
      await executor.confirm();
      final result = await pending;

      final captured = verify(bills.addBudgetedExpense(captureAny,
              applyToFuture: captureAnyNamed('applyToFuture')))
          .captured;
      final written = captured[0] as BudgetedExpense;
      expect(written.name, 'Braces');
      expect(written.allocatedAmount, 3000);
      expect(written.budgetedType, SetAsideType.goal);
      // A set-aside is a transfer between the user's own accounts, never
      // spending, so it carries no expense category.
      expect(written.categoryId, '');
      expect(result.ok, isTrue);
      expect(executor.pending, isNull);
    });

    test('declining writes nothing and reports a decline, not a success',
        () async {
      final pending = executor.propose(call(
          'addSetAside', {'name': 'Braces', 'amount': 3000, 'type': 'goal'}));
      await Future<void>.delayed(Duration.zero);
      executor.decline();
      final result = await pending;

      expect(result.ok, isFalse);
      expect(result.summary, contains('declined'));
      verifyNever(bills.addBudgetedExpense(any,
          applyToFuture: anyNamed('applyToFuture')));
      expect(executor.pending, isNull);
    });

    test('recurrence scope defaults narrow and comes from confirm, not the AI',
        () async {
      when(bills.addBudgetedExpense(any,
              applyToFuture: anyNamed('applyToFuture')))
          .thenAnswer((_) async {});

      // The model asks for a recurring set-aside and cannot say anything about
      // spreading it across future months — applyToFuture is not in the schema.
      final pending = executor.propose(call('addSetAside', {
        'name': 'Braces',
        'amount': 3000,
        'type': 'goal',
        'isRecurring': true,
        'applyToFuture': true, // ignored even if the model smuggles it in
      }));
      await Future<void>.delayed(Duration.zero);
      await executor.confirm(); // card default
      await pending;

      final scope = verify(bills.addBudgetedExpense(any,
              applyToFuture: captureAnyNamed('applyToFuture')))
          .captured
          .single;
      expect(scope, isFalse);
    });

    test('the user can widen the scope from the card', () async {
      when(bills.addBudgetedExpense(any,
              applyToFuture: anyNamed('applyToFuture')))
          .thenAnswer((_) async {});

      final pending = executor.propose(call(
          'addSetAside', {'name': 'Braces', 'amount': 3000, 'type': 'goal'}));
      await Future<void>.delayed(Duration.zero);
      await executor.confirm(applyToFuture: true);
      await pending;

      final scope = verify(bills.addBudgetedExpense(any,
              applyToFuture: captureAnyNamed('applyToFuture')))
          .captured
          .single;
      expect(scope, isTrue);
    });

    test('a second proposal while one is pending is refused, not dropped',
        () async {
      unawaited(executor.propose(call('addSetAside',
          {'name': 'Braces', 'amount': 3000, 'type': 'goal'}, 'tu_1')));
      await Future<void>.delayed(Duration.zero);

      final second = await executor.propose(call('addBill',
          {'name': 'Internet', 'amount': 999, 'dueDay': 15}, 'tu_2'));

      // Silently dropping it would strand the first future forever.
      expect(second.ok, isFalse);
      expect(second.summary, contains('still waiting'));
      expect(executor.pending!.call.id, 'tu_1');
    });
  });
}

/// Local `unawaited` so the test does not depend on dart:async's import.
void unawaited(Future<void> future) {}
