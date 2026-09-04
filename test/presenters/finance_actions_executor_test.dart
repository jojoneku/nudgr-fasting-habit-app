import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
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

  _transactionTests();
}

/// Local `unawaited` so the test does not depend on dart:async's import.
void unawaited(Future<void> future) {}

/// `addTransaction` runs against a real [LedgerPresenter] rather than a mock:
/// the point of these tests is that a resolved name lands on the right record,
/// and a mock would only prove the executor called something.
void _transactionTests() {
  const month = '2026-09';

  FinancialAccount account(String id, String name) => FinancialAccount(
        id: id,
        name: name,
        category: AccountCategory.ewallet,
        balance: 10000,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );

  FinanceCategory category(String id, String name, CategoryType type) =>
      FinanceCategory(
        id: id,
        name: name,
        type: type,
        colorHex: '#FFFFFF',
        icon: 'tag',
      );

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockBillsReceivablesPresenter bills;
  late LedgerPresenter ledger;
  late FinanceActionsExecutor executor;

  Future<void> ready() async {
    for (var i = 0; i < 60 && ledger.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Proposes, lets the card render, answers, and returns what the model sees.
  Future<AiToolResult> answer(AiToolCall c, {required bool yes}) async {
    final result = executor.propose(c);
    await Future<void>.delayed(Duration.zero);
    if (executor.pending == null) return result; // rejected before the card
    if (yes) {
      await executor.confirm();
    } else {
      executor.decline();
    }
    return result;
  }

  setUp(() async {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn(month);
    when(bills.allBills).thenReturn([]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([]);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer(
        (_) async => [account('a_gcash', 'GCash'), account('a_bpi', 'BPI')]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          category('c_food', 'Food', CategoryType.expense),
          category('c_transport', 'Transport', CategoryType.expense),
          category('c_salary', 'Salary', CategoryType.income),
        ]);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    executor = FinanceActionsExecutor(bills: bills, ledger: ledger);
    await ready();
  });

  tearDown(() => ledger.dispose());

  group('addTransaction — proposing', () {
    test('nothing is written until the user confirms', () async {
      unawaited(executor.propose(call('addTransaction', {
        'amount': 250,
        'description': 'Lunch at Alturas',
        'account': 'GCash',
        'category': 'Food',
      })));
      await Future<void>.delayed(Duration.zero);

      expect(executor.pending, isNotNull);
      expect(ledger.allTransactions, isEmpty);
    });

    test('the card names the account and category the model only spelled',
        () async {
      unawaited(executor.propose(call('addTransaction', {
        'amount': 250,
        'description': 'Lunch at Alturas',
        'account': 'gcash',
        'category': 'foo',
      })));
      await Future<void>.delayed(Duration.zero);

      final action = executor.pending!;
      expect(action.title, contains('Log expense'));
      expect(action.title, contains('Lunch at Alturas'));
      final rows = {for (final r in action.details) r.label: r.value};
      expect(rows['Account'], 'GCash');
      expect(rows['Category'], 'Food');
    });

    test('a transaction is never recurring, so the card offers no scope choice',
        () async {
      unawaited(executor.propose(call('addTransaction', {
        'amount': 250,
        'description': 'Lunch',
        'account': 'GCash',
        'category': 'Food',
        // Even if the model sends it, a single dated event has no series.
        'isRecurring': true,
      })));
      await Future<void>.delayed(Duration.zero);

      expect(executor.pending!.isRecurring, isFalse);
    });

    test('a decline writes nothing and is reported as a decline', () async {
      final result = await answer(
        call('addTransaction', {
          'amount': 250,
          'description': 'Lunch',
          'account': 'GCash',
          'category': 'Food',
        }),
        yes: false,
      );

      expect(result.ok, isFalse);
      expect(ledger.allTransactions, isEmpty);
    });
  });

  group('addTransaction — writing', () {
    test('a confirmed expense lands as an outflow on the resolved ids',
        () async {
      final result = await answer(
        call('addTransaction', {
          'amount': 250,
          'description': 'Lunch at Alturas',
          'account': 'BPI',
          'category': 'Food',
          'date': '2026-09-02',
          'note': 'with jana',
        }),
        yes: true,
      );

      expect(result.ok, isTrue);
      final txn = ledger.allTransactions.single;
      expect(txn.type, TransactionType.outflow);
      expect(txn.amount, 250);
      expect(txn.accountId, 'a_bpi');
      expect(txn.categoryId, 'c_food');
      expect(txn.description, 'Lunch at Alturas');
      expect(txn.note, 'with jana');
      expect(txn.date, DateTime(2026, 9, 2));
      // The month key is derived from the date, not from whatever month the
      // user happened to be reading.
      expect(txn.month, '2026-09');
    });

    test('income files as an inflow under an income category', () async {
      await answer(
        call('addTransaction', {
          'type': 'income',
          'amount': 30000,
          'description': 'September pay',
          'account': 'BPI',
          'category': 'Salary',
        }),
        yes: true,
      );

      final txn = ledger.allTransactions.single;
      expect(txn.type, TransactionType.inflow);
      expect(txn.categoryId, 'c_salary');
    });

    test('a transfer books both legs and neither is spending', () async {
      await answer(
        call('addTransaction', {
          'type': 'transfer',
          'amount': 5000,
          'description': 'Top up savings',
          'account': 'GCash',
          'toAccount': 'BPI',
        }),
        yes: true,
      );

      final legs = ledger.allTransactions;
      expect(legs, hasLength(2));
      expect(legs.map((t) => t.type).toSet(),
          {TransactionType.outflow, TransactionType.inflow});
      // Both legs share a group so the pair can be undone as one.
      expect(legs.map((t) => t.transferGroupId).toSet(), hasLength(1));
      expect(legs.first.transferGroupId, isNotNull);
    });

    test('a reimbursable expense is flagged and carries its payback link',
        () async {
      await answer(
        call('addTransaction', {
          'amount': 800,
          'description': 'Spotted Jana',
          'account': 'GCash',
          'category': 'Food',
          'reimbursable': true,
          'owedBy': 'Jana',
        }),
        yes: true,
      );

      final txn = ledger.allTransactions.single;
      expect(txn.reimbursable, isTrue);
      expect(txn.owedBy, 'Jana');
      expect(txn.reimbursementReceivableId, isNotNull);
    });

    test('reimbursable is ignored on income, which has nothing to pay back',
        () async {
      await answer(
        call('addTransaction', {
          'type': 'income',
          'amount': 500,
          'description': 'Refund',
          'account': 'GCash',
          'category': 'Salary',
          'reimbursable': true,
        }),
        yes: true,
      );

      expect(ledger.allTransactions.single.reimbursable, isFalse);
    });

    test('an omitted date files the entry today, not on the viewed month',
        () async {
      await answer(
        call('addTransaction', {
          'amount': 100,
          'description': 'Jeep',
          'account': 'GCash',
          'category': 'Transport',
        }),
        yes: true,
      );

      final now = DateTime.now();
      expect(ledger.allTransactions.single.date,
          DateTime(now.year, now.month, now.day));
    });
  });

  group('addTransaction — refusals that teach', () {
    Future<AiToolResult> reject(Map<String, Object?> input) =>
        executor.propose(call('addTransaction', input));

    test('an unnamed account with several to choose from names them all',
        () async {
      final result = await reject({
        'amount': 250,
        'description': 'Lunch',
        'category': 'Food',
      });

      expect(result.ok, isFalse);
      expect(result.summary, contains('GCash'));
      expect(result.summary, contains('BPI'));
      // Nothing was put in front of the user to confirm.
      expect(executor.pending, isNull);
    });

    test('a sole account is used without asking', () async {
      when(storage.loadAccounts())
          .thenAnswer((_) async => [account('a_gcash', 'GCash')]);
      final solo = LedgerPresenter(storage, stats);
      for (var i = 0; i < 60 && solo.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final soloExecutor = FinanceActionsExecutor(bills: bills, ledger: solo);

      unawaited(soloExecutor.propose(call('addTransaction', {
        'amount': 250,
        'description': 'Lunch',
        'category': 'Food',
      })));
      await Future<void>.delayed(Duration.zero);

      final rows = {
        for (final r in soloExecutor.pending!.details) r.label: r.value
      };
      expect(rows['Account'], 'GCash');
      solo.dispose();
    });

    test('an account name that matches nothing lists the real ones', () async {
      final result = await reject({
        'amount': 250,
        'description': 'Lunch',
        'account': 'Metrobank',
        'category': 'Food',
      });

      expect(result.ok, isFalse);
      expect(result.summary, contains('Metrobank'));
      expect(result.summary, contains('GCash'));
    });

    test('an expense cannot be filed under an income category', () async {
      final result = await reject({
        'amount': 250,
        'description': 'Lunch',
        'account': 'GCash',
        'category': 'Salary',
      });

      // Filing it anyway would count spending as earning in every total that
      // reads the category type.
      expect(result.ok, isFalse);
      // The rejected name is quoted back so the model can see what it got
      // wrong, but it is not offered among the options it may retry with.
      expect(result.summary, contains('matches "Salary"'));
      final options = result.summary.split('They are:').last;
      expect(options, contains('"Food"'));
      expect(options, isNot(contains('Salary')));
    });

    test('a missing category is refused rather than left blank', () async {
      final result = await reject({
        'amount': 250,
        'description': 'Lunch',
        'account': 'GCash',
      });

      expect(result.ok, isFalse);
      expect(result.summary, contains('Which category'));
    });

    test('a transfer to the same account is refused', () async {
      final result = await reject({
        'type': 'transfer',
        'amount': 500,
        'description': 'Shuffle',
        'account': 'GCash',
        'toAccount': 'GCash',
      });

      expect(result.ok, isFalse);
      expect(result.summary, contains('two different accounts'));
    });

    test('a transfer with no destination says so', () async {
      final result = await reject({
        'type': 'transfer',
        'amount': 500,
        'description': 'Shuffle',
        'account': 'GCash',
      });

      expect(result.ok, isFalse);
      expect(result.summary, contains('toAccount'));
    });

    test('a zero or negative amount is refused', () async {
      for (final bad in [0, -250]) {
        final result = await reject({
          'amount': bad,
          'description': 'Lunch',
          'account': 'GCash',
          'category': 'Food',
        });
        expect(result.ok, isFalse, reason: 'amount $bad');
        expect(result.summary, contains('positive'));
      }
    });

    test('a future-dated entry is refused and points at bills instead',
        () async {
      final next = DateTime.now().add(const Duration(days: 7));
      final iso = '${next.year.toString().padLeft(4, '0')}-'
          '${next.month.toString().padLeft(2, '0')}-'
          '${next.day.toString().padLeft(2, '0')}';

      final result = await reject({
        'amount': 250,
        'description': 'Next week groceries',
        'account': 'GCash',
        'category': 'Food',
        'date': iso,
      });

      expect(result.ok, isFalse);
      expect(result.summary, contains('future-dated'));
      expect(result.summary, contains('bill'));
    });

    test('an unknown type is refused rather than booked as an expense',
        () async {
      final result = await reject({
        'type': 'refund',
        'amount': 250,
        'description': 'Lunch',
        'account': 'GCash',
        'category': 'Food',
      });

      expect(result.ok, isFalse);
      expect(result.summary, contains('expense, income or transfer'));
    });

    test('no ledger wired reports that, rather than pretending to log',
        () async {
      final headless = FinanceActionsExecutor(bills: bills);

      final result = await headless.propose(call('addTransaction', {
        'amount': 250,
        'description': 'Lunch',
        'account': 'GCash',
        'category': 'Food',
      }));

      expect(result.ok, isFalse);
      expect(result.summary, contains('ledger is not available'));
    });
  });
}
