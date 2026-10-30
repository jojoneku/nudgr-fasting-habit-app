import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 4 parity: set, edit and remove a budget from chat through
/// the Budget tab's own presenter calls. Each row shows exactly what the
/// approve saves; a savings budget offers its set-aside on the row (D8).

final _now = DateTime.now();
String _month(int offset) =>
    toMonthKey(DateTime(_now.year, _now.month + offset));

FinancialAccount _acc(String id, String name, AccountCategory c) =>
    FinancialAccount(
      id: id,
      name: name,
      category: c,
      balance: 0,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

FinanceCategory _cat(String id, String name) => FinanceCategory(
      id: id,
      name: name,
      type: CategoryType.expense,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

/// Groceries ₱5000 in last, this and next month: one recurring series.
List<Budget> _series({bool recurring = true}) => [
      for (final offset in [-1, 0, 1])
        Budget(
          id: 'g$offset',
          categoryId: 'groc',
          month: _month(offset),
          allocatedAmount: 5000,
          group: BudgetGroupDef.idVariableOptional,
          budgetType: BudgetType.monthly,
          seriesId: recurring ? 'g-1' : null,
          isRecurring: recurring,
        ),
    ];

void main() {
  late MockStorageService storage;
  late MockBillsReceivablesPresenter bills;
  late BudgetPresenter budget;
  late FinanceActionsExecutor ex;
  late List<Budget> saved;

  Future<void> build(List<Budget> seed) async {
    storage = MockStorageService();
    final stats = MockStatsPresenter();
    saved = [...seed];
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          _acc('bpi', 'BPI', AccountCategory.bank),
          _acc('ef', 'Emergency Fund', AccountCategory.savings),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer(
        (_) async => [_cat('groc', 'Groceries'), _cat('fun', 'Fun')]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBudgets()).thenAnswer((_) async => saved);
    when(storage.saveBudgets(any)).thenAnswer((inv) async {
      saved = List<Budget>.from(inv.positionalArguments.first);
    });
    when(storage.loadBudgetGroups())
        .thenAnswer((_) async => <BudgetGroupDef>[]);
    when(storage.loadBudgetedExpenses())
        .thenAnswer((_) async => <BudgetedExpense>[]);
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn(_month(0));
    when(bills.allBills).thenReturn([]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([]);
    when(bills.addBudgetedExpense(any,
            applyToFuture: anyNamed('applyToFuture')))
        .thenAnswer((_) async {});

    final ledger = LedgerPresenter(storage, stats);
    while (ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    budget = BudgetPresenter(
        storage, stats, ledger, MockNotificationService(), null, bills);
    await budget.load();
    ex = FinanceActionsExecutor(bills: bills, budget: budget, ledger: ledger);
  }

  Map<String, String> rows() =>
      {for (final d in ex.pending!.details) d.label: d.value};
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  AiToolCall call(String name, Map<String, Object?> input) =>
      AiToolCall(id: 'c1', name: name, input: input);
  Budget? row(String id) =>
      budget.allBudgets.where((b) => b.id == id).firstOrNull;

  test('one kind per tool, and no recurrence scope field', () {
    final kinds = {
      'setBudget': AiToolKind.create,
      'editBudget': AiToolKind.update,
      'removeBudget': AiToolKind.destroy,
    };
    for (final e in kinds.entries) {
      final tool = financeToolNamed(e.key)!;
      expect(tool.kind, e.value, reason: e.key);
      final props = tool.inputSchema['properties'] as Map;
      expect(props.containsKey('applyToFuture'), isFalse, reason: e.key);
      expect(props.keys.any((k) => '$k'.startsWith('_')), isFalse,
          reason: e.key);
    }
  });

  group('setBudget', () {
    test('a spending budget: T1 row shows what is saved', () async {
      await build([]);
      final answer =
          ex.propose(call('setBudget', {'category': 'fun', 'amount': 2000}));
      await settle();

      expect(ex.pending!.tier, ProposalTier.create);
      expect(ex.pending!.option, isNull);
      expect(rows(), {
        'Category': 'Fun',
        'Amount': '₱2000',
        'Month': _month(0),
        'Group': 'Variable',
        'Repeats': 'Every month until removed',
      });

      await ex.confirm();
      expect((await answer).ok, isTrue);
      final b = budget.budgetFor('fun', month: _month(0))!;
      expect(b.allocatedAmount, 2000);
      expect(b.group, BudgetGroupDef.idVariableOptional);
      expect(b.isRecurring, isTrue);
      verifyNever(bills.addBudgetedExpense(any,
          applyToFuture: anyNamed('applyToFuture')));
    });

    test('a savings budget offers its set-aside; ticked, both are saved',
        () async {
      await build([]);
      // A model that sends the card-only key is ignored: the user ticks it.
      final answer = ex.propose(call('setBudget', {
        'savingsAccount': 'Emergency',
        'amount': 3000,
        '_addSetAside': true,
      }));
      await settle();

      expect(rows()['Set aside into'], 'Emergency Fund');
      expect(rows()['Group'], 'Savings');
      expect(ex.pending!.option!.value, isFalse);
      expect(rows().containsKey('Also adds'), isFalse);

      expect(ex.editAction('c1', {'_addSetAside': true}), isNull);
      expect(ex.pending!.option!.value, isTrue);
      expect(rows()['Also adds'],
          'a monthly ₱3000 set-aside into Emergency Fund in Bills');

      await ex.confirm();
      expect((await answer).summary, contains('set-aside'));
      expect(budget.budgetFor('ef', month: _month(0))!.group,
          BudgetGroupDef.idSavings);
      final added = verify(bills.addBudgetedExpense(captureAny,
              applyToFuture: anyNamed('applyToFuture')))
          .captured
          .single as BudgetedExpense;
      expect(added.destinationAccountId, 'ef');
      expect(added.allocatedAmount, 3000);
      expect(added.month, _month(0));
    });

    test('a savings budget left unticked adds no set-aside', () async {
      await build([]);
      final answer = ex.propose(
          call('setBudget', {'savingsAccount': 'Emergency', 'amount': 3000}));
      await settle();
      await ex.confirm();
      await answer;
      expect(budget.budgetFor('ef', month: _month(0)), isNotNull);
      verifyNever(bills.addBudgetedExpense(any,
          applyToFuture: anyNamed('applyToFuture')));
    });

    test('an existing budget, an unknown category or both keys are refused',
        () async {
      await build(_series());
      final existing = await ex
          .propose(call('setBudget', {'category': 'Groceries', 'amount': 1}));
      expect(existing.summary, contains('editBudget'));
      expect(existing.summary, contains('id=g0'));
      final unknown = await ex
          .propose(call('setBudget', {'category': 'Pets', 'amount': 100}));
      expect(unknown.summary, contains('No expense category'));
      final both = await ex.propose(call('setBudget',
          {'category': 'Fun', 'savingsAccount': 'Emergency', 'amount': 100}));
      expect(both.ok, isFalse);
      expect(ex.batch, isNull);
      expect(budget.allBudgets, hasLength(3));
    });
  });

  group('editBudget', () {
    test('a recurring budget is T3: this and later months change, not earlier',
        () async {
      await build(_series());
      final answer =
          ex.propose(call('editBudget', {'id': 'g0', 'amount': 6000}));
      await settle();

      expect(ex.pending!.tier, ProposalTier.destructive);
      expect(rows()['Amount'], '₱5000 → ₱6000');
      expect(rows()['Also changes'],
          'every later month of this budget; earlier months keep theirs');

      await ex.confirm();
      expect((await answer).summary, contains('every later month'));
      expect(row('g-1')!.allocatedAmount, 5000);
      expect(row('g0')!.allocatedAmount, 6000);
      expect(row('g1')!.allocatedAmount, 6000);
    });

    test('a one-month budget is T2 and only that month changes', () async {
      await build(_series(recurring: false));
      final answer =
          ex.propose(call('editBudget', {'id': 'g0', 'amount': 4000}));
      await settle();
      expect(ex.pending!.tier, ProposalTier.change);
      expect(rows().containsKey('Also changes'), isFalse);

      await ex.confirm();
      await answer;
      expect(row('g0')!.allocatedAmount, 4000);
      expect(row('g1')!.allocatedAmount, 5000);
    });

    test('a bad id, no change and a savings group are refused before any row',
        () async {
      await build(_series());
      final bad =
          await ex.propose(call('editBudget', {'id': 'nope', 'amount': 1}));
      expect(bad.summary, contains('"nope"'));
      expect(bad.summary, contains('find (entity budget)'));
      final same =
          await ex.propose(call('editBudget', {'id': 'g0', 'amount': 5000}));
      expect(same.summary, contains('changes nothing'));
      final group = await ex
          .propose(call('editBudget', {'id': 'g0', 'group': 'Savings'}));
      expect(group.summary, contains('spending group'));
      expect(ex.batch, isNull);
      expect(row('g0')!.allocatedAmount, 5000);
    });
  });

  group('removeBudget', () {
    test('T3 row; removes this and later months, earlier months stay',
        () async {
      await build(_series());
      final answer = ex.propose(call('removeBudget', {'id': 'g0'}));
      await settle();

      expect(ex.pending!.tier, ProposalTier.destructive);
      expect(rows()['Budget'], 'Groceries');
      expect(rows()['Month'], _month(0));
      expect(rows()['Also'], contains('later months lose it too'));

      await ex.confirm();
      expect((await answer).ok, isTrue);
      expect(row('g0'), isNull);
      expect(row('g1'), isNull);
      expect(row('g-1')!.isRecurring, isFalse);
    });

    test('a bad id is refused before any row', () async {
      await build(_series());
      final r = await ex.propose(call('removeBudget', {'id': 'nope'}));
      expect(r.ok, isFalse);
      expect(r.summary, contains('"nope"'));
      expect(ex.batch, isNull);
      expect(budget.allBudgets, hasLength(3));
    });
  });
}
