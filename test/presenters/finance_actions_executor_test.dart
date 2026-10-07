import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/extracted_entry.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/model_date_guard.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

FinancialAccount _acc(String id, String name) => FinancialAccount(
      id: id,
      name: name,
      category: AccountCategory.bank,
      balance: 1000,
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
    test('a month the model slipped back to its training year is rebased',
        () async {
      final now = DateTime.now();
      final mm = now.month.toString().padLeft(2, '0');

      unawaited(executor.propose(call('addBill', {
        'name': 'Internet',
        'amount': 999,
        'dueDay': 24,
        'month': '${now.year - 2}-$mm',
      })));
      await Future<void>.delayed(Duration.zero);

      final month =
          executor.pending!.details.firstWhere((d) => d.label == 'Month').value;
      expect(month, '${now.year}-$mm');
    });

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

  group('logTransactions', () {
    late MockStorageService storage;
    late MockStatsPresenter stats;

    setUp(() {
      storage = MockStorageService();
      stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts())
          .thenAnswer((_) async => [_acc('cash', 'CASH')]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [_cat('transpo', 'Transportation')]);
      when(storage.loadTransactions()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
      when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
      when(stats.addXp(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());
    });

    Future<LedgerPresenter> ledger() async {
      final p = LedgerPresenter(storage, stats);
      while (p.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return p;
    }

    AiToolCall logCall(List<Map<String, Object?>> entries) =>
        call('logTransactions', {'entries': entries});

    test('the rows land on the review card and nothing is written', () async {
      final led = await ledger();
      final executor = FinanceActionsExecutor(bills: bills, ledger: led);

      final result = await executor.propose(logCall([
        {
          'amount': 295,
          'description': 'Motor Oil Change - Oil',
          'type': 'outflow',
          'account': 'CASH',
          'category': 'Transportation',
        },
        {
          'amount': 50,
          'description': 'Motor Oil Change - Labour',
          'type': 'outflow',
          'account': 'CASH',
          'category': 'Transportation',
        },
      ]));

      expect(result.ok, isTrue);
      // The model must not narrate a save: the card is still waiting.
      expect(result.summary, contains('NOT SAVED YET'));
      expect(led.chatState.entries.length, 2);
      expect(led.chatState.entries.first.txn.amount, 295);
      expect(led.chatState.entries.first.txn.accountId, 'cash');
      expect(led.chatState.entries.first.txn.categoryId, 'transpo');
      expect(led.chatState.entries.every((e) => e.isReady), isTrue);
      // No proposal card: the review card is this tool's confirm surface.
      expect(executor.pending, isNull);
      expect(led.allTransactions, isEmpty);
    });

    test('an account name the model invented becomes a gap, not an id',
        () async {
      final led = await ledger();
      final executor = FinanceActionsExecutor(bills: bills, ledger: led);

      final result = await executor.propose(logCall([
        {
          'amount': 130,
          'description': 'Lunch At Alvas',
          'account': 'Imaginary Wallet',
          'category': 'Transportation',
        },
      ]));

      final entry = led.chatState.entries.single;
      expect(entry.txn.accountId, isNull);
      expect(entry.missing, contains(EntryField.account));
      expect(result.summary, contains('still needs'));
    });

    test('entries with nothing usable are reported as unreadable', () async {
      final led = await ledger();
      final executor = FinanceActionsExecutor(bills: bills, ledger: led);

      final result = await executor.propose(logCall([
        {'description': 'something'},
      ]));

      expect(result.ok, isFalse);
      expect(led.chatState.entries, isEmpty);
    });

    test('a build with no ledger says so instead of pretending', () async {
      final result = await executor.propose(logCall([
        {'amount': 100, 'description': 'Gas', 'account': 'CASH'},
      ]));

      expect(result.ok, isFalse);
      expect(result.summary, contains('not available'));
    });
  });

  group('findTransactions', () {
    late MockStorageService storage;
    late MockStatsPresenter stats;

    TransactionRecord txn(
      String id,
      DateTime date,
      double amount,
      String description, {
      TransactionType type = TransactionType.outflow,
      String account = 'cash',
      String category = 'transpo',
      String? note,
      String? transferTo,
      String? group,
      bool reimbursable = false,
      String? owedBy,
    }) =>
        TransactionRecord(
          id: id,
          date: date,
          accountId: account,
          categoryId: category,
          amount: amount,
          type: type,
          description: description,
          note: note,
          month: '${date.year}-${date.month.toString().padLeft(2, '0')}',
          transferToAccountId: transferTo,
          transferGroupId: group,
          reimbursable: reimbursable,
          owedBy: owedBy,
        );

    final history = [
      txn('t1', DateTime(2026, 9, 14), 245, 'Grab ride', note: 'to office'),
      txn('t2', DateTime(2026, 9, 2), 1200, 'Groceries', category: 'food'),
      txn('t3', DateTime(2026, 3, 9), 180, 'Grab ride'),
      txn('t4', DateTime(2026, 9, 1), 30000, 'Salary',
          type: TransactionType.inflow, category: 'salary'),
      // Both legs of one transfer: only the outflow leg is listed.
      txn('t5', DateTime(2026, 9, 5), 5000, 'Move to savings',
          account: 'cash', transferTo: 'bpi', group: 'g1'),
      txn('t6', DateTime(2026, 9, 5), 5000, 'Move to savings',
          type: TransactionType.inflow,
          account: 'bpi',
          transferTo: 'cash',
          group: 'g1'),
      txn('t7', DateTime(2026, 9, 10), 800, 'Client lunch',
          category: 'food', reimbursable: true, owedBy: 'Acme'),
    ];

    setUp(() {
      storage = MockStorageService();
      stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer(
          (_) async => [_acc('cash', 'CASH'), _acc('bpi', 'BPI Savings')]);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => [
            _cat('transpo', 'Transportation'),
            _cat('food', 'Food'),
            _cat('salary', 'Salary'),
          ]);
      when(storage.loadTransactions()).thenAnswer((_) async => history);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
      when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
      when(stats.addXp(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());
    });

    Future<FinanceActionsExecutor> withLedger() async {
      final p = LedgerPresenter(storage, stats);
      while (p.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return FinanceActionsExecutor(bills: bills, ledger: p);
    }

    test('no filters reviews the month being viewed, newest first', () async {
      final ex = await withLedger();

      final result = await ex.runRead(call('findTransactions', {}));

      expect(result.ok, isTrue);
      expect(result.summary, contains('in 2026-09'));
      expect(result.summary, isNot(contains('2026-03-09')));
      final lines = result.summary.split('\n');
      expect(lines[1], contains('2026-09-14 "Grab ride"'));
      expect(lines[1], contains('note: "to office"'));
    });

    test('a query with no dates searches the whole history', () async {
      final ex = await withLedger();

      final result =
          await ex.runRead(call('findTransactions', {'query': 'grab'}));

      expect(result.summary, contains('2 transactions in all history'));
      expect(result.summary, contains('2026-03-09'));
      expect(result.summary, contains('Spent ₱425'));
    });

    test('a transfer is listed once and is neither spent nor received',
        () async {
      final ex = await withLedger();

      final result = await ex.runRead(
          call('findTransactions', {'month': '2026-09', 'type': 'transfer'}));

      expect(result.summary, contains('1 transactions'));
      expect(result.summary, contains('transfer CASH → BPI Savings'));
      expect(result.summary, contains('Spent ₱0, received ₱0'));
    });

    test('totals cover every match even when the list is capped', () async {
      final ex = await withLedger();

      final result = await ex.runRead(call('findTransactions',
          {'month': '2026-09', 'type': 'outflow', 'limit': 1}));

      // Grab 245 + Groceries 1200 + Client lunch 800.
      expect(result.summary, contains('Spent ₱2245'));
      expect(result.summary, contains('Showing the newest 1 of 3'));
      expect(result.summary.split('\n').length, 2);
    });

    test('date range, category and account filters narrow the list', () async {
      final ex = await withLedger();

      final result = await ex.runRead(call('findTransactions', {
        'from': '2026-09-01',
        'to': '2026-09-10',
        'category': 'foo',
        'account': 'cash',
      }));

      expect(result.summary, contains('2026-09-01 to 2026-09-10'));
      expect(result.summary, contains('Groceries'));
      expect(result.summary, contains('[reimbursable, owed by Acme]'));
      expect(result.summary, isNot(contains('Grab')));
    });

    test('a search before the ledger begins is read as a year slip', () async {
      final ex = await withLedger();

      // "Grab in March" with the model's year two years back.
      final result = await ex.runRead(
          call('findTransactions', {'month': '2024-03', 'query': 'grab'}));

      final rebased = rebaseStaleMonthKey('2024-03', DateTime.now());
      expect(rebased, isNot('2024-03'));
      expect(result.summary, contains('searched $rebased instead'));
    });

    test('rows carry ids so edit and delete can name the transaction',
        () async {
      final ex = await withLedger();

      final result =
          await ex.runRead(call('findTransactions', {'query': 'grab'}));

      expect(result.summary, contains('id=t1'));
      expect(result.summary, contains('id=t3'));
    });

    test('nothing matched tells the model not to invent rows', () async {
      final ex = await withLedger();

      final result =
          await ex.runRead(call('findTransactions', {'query': 'yacht'}));

      expect(result.ok, isTrue);
      expect(result.summary, contains('No transactions matched'));
      expect(result.summary, contains('Do not invent'));
    });

    test('a build with no ledger says so instead of pretending', () async {
      final result = await executor.runRead(call('findTransactions', {}));

      expect(result.ok, isFalse);
      expect(result.summary, contains('not available'));
    });
  });

  group('addInstallment', () {
    late MockStorageService storage;
    late MockStatsPresenter stats;
    late List<Installment> savedPlans;

    FinancialAccount credit(String id, String name,
            {AccountCategory category = AccountCategory.creditCard,
            bool isActive = true}) =>
        FinancialAccount(
          id: id,
          name: name,
          category: category,
          balance: 0,
          creditLimit: 100000,
          colorHex: '#FFFFFF',
          icon: 'card',
          isActive: isActive,
        );

    final everyAccount = [
      credit('bdo', 'BDO Card'),
      credit('amore', 'BPI Amore'),
      credit('gold', 'BPI Gold'),
      credit('spl', 'SPayLater', category: AccountCategory.bnpl),
      credit('old', 'Old Card', isActive: false),
      _acc('mari', 'MariBank'),
    ];

    String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';

    Map<String, Object?> plan([Map<String, Object?> overrides = const {}]) => {
          'name': 'Phone',
          'amount': 12000,
          'months': 6,
          'account': 'SPayLater',
          ...overrides,
        };

    setUp(() {
      storage = MockStorageService();
      stats = MockStatsPresenter();
      savedPlans = [];
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => everyAccount);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadTransactions()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.loadInstallments()).thenAnswer((_) async => savedPlans);
      when(storage.saveInstallments(any)).thenAnswer((inv) async {
        savedPlans =
            List<Installment>.from(inv.positionalArguments.first as List);
      });
      when(stats.addXp(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());
    });

    Future<(FinanceActionsExecutor, LedgerPresenter)> withLedger(
        [List<FinancialAccount>? accounts]) async {
      if (accounts != null) {
        when(storage.loadAccounts()).thenAnswer((_) async => accounts);
      }
      final p = LedgerPresenter(storage, stats);
      while (p.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return (FinanceActionsExecutor(bills: bills, ledger: p), p);
    }

    /// Proposes and expects a refusal: nothing parked, nothing to confirm.
    Future<String> refused(
        FinanceActionsExecutor ex, Map<String, Object?> input) async {
      final result = await ex.propose(call('addInstallment', input));
      expect(result.ok, isFalse, reason: result.summary);
      expect(ex.pending, isNull);
      return result.summary;
    }

    String detail(FinanceActionsExecutor ex, String label) =>
        ex.pending!.details.firstWhere((d) => d.label == label).value;

    test('the card shows the account it resolved, not the model\'s words',
        () async {
      final (ex, _) = await withLedger();

      for (final (said, resolved) in [
        ('spaylater', 'SPayLater'),
        ('BDO', 'BDO Card'),
        ('BDO Card Visa', 'BDO Card'),
        ('bpi amore', 'BPI Amore'),
      ]) {
        unawaited(ex.propose(call('addInstallment', plan({'account': said}))));
        expect(detail(ex, 'Account'), resolved, reason: said);
        ex.decline();
      }
    });

    test('confirming books the plan on the account the card showed', () async {
      final (ex, ledger) = await withLedger();

      final future =
          ex.propose(call('addInstallment', plan({'account': 'bdo'})));
      expect(detail(ex, 'Account'), 'BDO Card');
      await ex.confirm();
      final result = await future;

      expect(result.ok, isTrue);
      expect(result.summary, contains('on BDO Card'));
      expect(savedPlans.single.accountId, 'bdo');
      final purchase = ledger.allTransactions.single;
      expect(purchase.isInstallment, isTrue);
      expect(purchase.accountId, 'bdo');
      expect(purchase.installmentId, savedPlans.single.id);
    });

    test('an ambiguous account is refused with the choices', () async {
      final (ex, _) = await withLedger();

      final reason = await refused(ex, plan({'account': 'BPI'}));

      expect(reason, contains('more than one credit account'));
      expect(reason, contains('"BPI Amore"'));
      expect(reason, contains('"BPI Gold"'));
    });

    test('a bank account is refused, never booked as an installment', () async {
      final (ex, _) = await withLedger();

      final reason = await refused(ex, plan({'account': 'MariBank'}));

      expect(reason, contains('"MariBank" is not a credit account'));
      expect(reason, contains('"SPayLater"'));
    });

    test('an unknown or archived account is refused, listing active ones',
        () async {
      final (ex, _) = await withLedger();

      final unknown = await refused(ex, plan({'account': 'Metrobank'}));
      expect(unknown, contains('No credit account matches "Metrobank"'));
      expect(unknown, contains('"BDO Card"'));
      expect(unknown, isNot(contains('Old Card')));

      final archived = await refused(ex, plan({'account': 'Old Card'}));
      expect(archived, contains('No credit account matches'));
    });

    test('no account is refused when there is more than one credit account',
        () async {
      final (ex, _) = await withLedger();

      final reason = await refused(ex, plan({'account': null}));

      expect(reason, contains('No account was given'));
    });

    test('no account uses the only credit account, and the card names it',
        () async {
      final (ex, _) = await withLedger(
          [credit('spl', 'SPayLater', category: AccountCategory.bnpl)]);

      unawaited(ex.propose(call('addInstallment', plan({'account': null}))));

      expect(detail(ex, 'Account'), 'SPayLater');
    });

    test('a user with no credit accounts gets a clear failure', () async {
      final (ex, _) = await withLedger([_acc('mari', 'MariBank')]);

      final reason = await refused(ex, plan({'account': 'MariBank'}));

      expect(reason, contains('no credit card, credit line or BNPL account'));
    });

    test('an amount of zero, below zero or missing is refused', () async {
      final (ex, _) = await withLedger();

      for (final amount in [0, -500, null, 'lots']) {
        final reason = await refused(ex, plan({'amount': amount}));
        expect(reason, contains('above zero'), reason: '$amount');
      }
    });

    test('a negative or implausible interest rate is refused', () async {
      final (ex, _) = await withLedger();

      expect(await refused(ex, plan({'interestRate': -1})),
          contains('cannot be negative'));
      // 18% is a yearly rate given as monthly.
      expect(await refused(ex, plan({'interestRate': 18})),
          contains('divide it by 12'));
      expect(await refused(ex, plan({'interestRate': 'abc'})),
          contains('must be a number'));
    });

    test('a real monthly rate is accepted and shown', () async {
      final (ex, _) = await withLedger();

      unawaited(ex.propose(call('addInstallment', plan({'interestRate': 3}))));

      expect(detail(ex, 'Interest rate'), '3% / mo');
    });

    test('missing, single or fractional months are refused, never clamped',
        () async {
      final (ex, _) = await withLedger();

      expect(await refused(ex, plan({'months': null})),
          contains('How many monthly payments'));
      expect(await refused(ex, plan({'months': 1})), contains('at least 2'));
      expect(
          await refused(ex, plan({'months': 6.5})), contains('whole number'));
      expect(await refused(ex, plan({'months': 600})),
          contains('longer than any installment plan'));
    });

    test('a date the model slipped back a year is rebased, and says so',
        () async {
      final (ex, _) = await withLedger();
      final now = DateTime.now();
      final slipped = DateTime(now.year - 2, now.month, 1);
      final expected = rebaseStaleDate(slipped, now);

      unawaited(
          ex.propose(call('addInstallment', plan({'date': iso(slipped)}))));

      expect(detail(ex, 'Purchase date'),
          '${iso(expected)} (moved from ${iso(slipped)})');
    });

    test('a future or unreadable purchase date is refused', () async {
      final (ex, _) = await withLedger();
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      expect(await refused(ex, plan({'date': iso(tomorrow)})),
          contains('in the future'));
      expect(await refused(ex, plan({'date': 'last week'})),
          contains('YYYY-MM-DD'));
    });

    test('a category that does not exist is shown as none, not as typed',
        () async {
      final (ex, _) = await withLedger();

      unawaited(
          ex.propose(call('addInstallment', plan({'category': 'Gadgets'}))));

      expect(detail(ex, 'Category'), contains('no category named "Gadgets"'));
    });
  });

  group('findAccounts', () {
    test('lists active accounts with balances and categories', () async {
      final storage = MockStorageService();
      final stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => [
            FinancialAccount(
              id: 'a1',
              name: 'GCash',
              category: AccountCategory.ewallet,
              balance: 1500,
              currency: 'PHP',
              colorHex: '#000000',
              icon: 'wallet',
            ),
            FinancialAccount(
              id: 'a2',
              name: 'BPI Credit Card',
              category: AccountCategory.creditCard,
              balance: 8000,
              creditLimit: 50000,
              currency: 'PHP',
              colorHex: '#FF0000',
              icon: 'credit-card',
            ),
          ]);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadTransactions()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());

      final ledger = LedgerPresenter(storage, stats);
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final ex = FinanceActionsExecutor(bills: bills, ledger: ledger);

      final result = await ex.runRead(call('findAccounts', {}));
      expect(result.ok, isTrue);
      expect(result.summary, contains('GCash'));
      expect(result.summary, contains('₱1500'));
      expect(result.summary, contains('BPI Credit Card'));
      expect(result.summary, contains('owed ₱8000'));
      expect(result.summary, contains('limit ₱50000'));
    });
  });

  group('settlements and mutations', () {
    test('markBillPaid proposes and confirms bill settlement', () async {
      final testBill = Bill(
        id: 'b1',
        name: 'Meralco',
        billType: BillType.utility,
        amount: 3500,
        dueDay: 15,
        month: '2026-09',
        categoryId: 'util',
      );
      when(bills.allBills).thenReturn([testBill]);

      unawaited(exPropose(
          executor, call('markBillPaid', {'id': 'b1', 'paidAmount': 3500})));
      await Future<void>.delayed(Duration.zero);

      expect(executor.pending, isNotNull);
      expect(executor.pending!.title, contains('Mark bill paid: Meralco'));
      expect(executor.pending!.confirmLabel, 'Mark Paid');

      await executor.confirm();
      verify(bills.markBillPaid('b1',
              paidAmount: 3500,
              paidDate: anyNamed('paidDate'),
              accountId: anyNamed('accountId')))
          .called(1);
    });

    test('markReceivableReceived proposes and confirms settlement', () async {
      final testRec = Receivable(
        id: 'r1',
        name: 'Alex loan',
        receivableType: ReceivableType.other,
        amount: 2000,
        month: '2026-09',
        categoryId: '',
      );
      when(bills.allReceivables).thenReturn([testRec]);

      unawaited(exPropose(
          executor,
          call(
              'markReceivableReceived', {'id': 'r1', 'receivedAmount': 2000})));
      await Future<void>.delayed(Duration.zero);

      expect(executor.pending, isNotNull);
      expect(executor.pending!.title, contains('Mark received: Alex loan'));
      expect(executor.pending!.confirmLabel, 'Mark Received');

      await executor.confirm();
      verify(bills.markReceivableReceived('r1',
              receivedAmount: 2000,
              receivedDate: anyNamed('receivedDate'),
              accountId: anyNamed('accountId')))
          .called(1);
    });

    test('editBill and deleteBill work through owning presenter', () async {
      final testBill = Bill(
        id: 'b2',
        name: 'Gym',
        billType: BillType.other,
        amount: 1500,
        dueDay: 5,
        month: '2026-09',
        categoryId: '',
      );
      when(bills.allBills).thenReturn([testBill]);

      // Edit
      unawaited(
          exPropose(executor, call('editBill', {'id': 'b2', 'amount': 1800})));
      await Future<void>.delayed(Duration.zero);
      expect(executor.pending!.title, contains('Update bill: Gym'));
      await executor.confirm();
      verify(bills.updateBill(any, applyToFuture: false)).called(1);

      // Delete
      unawaited(exPropose(executor, call('deleteBill', {'id': 'b2'})));
      await Future<void>.delayed(Duration.zero);
      expect(executor.pending!.title, contains('Delete bill: Gym'));
      expect(executor.pending!.isDestructive, isTrue);
      await executor.confirm();
      verify(bills.deleteBill('b2', applyToFuture: false)).called(1);
    });

    test('editTransaction and deleteTransaction mutate ledger', () async {
      final storage = MockStorageService();
      final stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => [
            _acc('cash', 'CASH'),
          ]);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => [
            _cat('food', 'Food'),
          ]);
      final txnRecord = TransactionRecord(
        id: 't_edit',
        date: DateTime(2026, 9, 10),
        accountId: 'cash',
        categoryId: 'food',
        amount: 150,
        type: TransactionType.outflow,
        description: 'Snack',
        month: '2026-09',
      );
      when(storage.loadTransactions()).thenAnswer((_) async => [txnRecord]);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());

      final ledger = LedgerPresenter(storage, stats);
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final ex = FinanceActionsExecutor(bills: bills, ledger: ledger);

      // Edit
      unawaited(exPropose(
          ex,
          call('editTransaction',
              {'id': 't_edit', 'description': 'Big Snack', 'amount': 200})));
      await Future<void>.delayed(Duration.zero);
      expect(ex.pending!.title, contains('Edit transaction: Snack'));
      await ex.confirm();

      final updated =
          ledger.allTransactions.firstWhere((t) => t.id == 't_edit');
      expect(updated.description, 'Big Snack');
      expect(updated.amount, 200);

      // Delete
      unawaited(exPropose(ex, call('deleteTransaction', {'id': 't_edit'})));
      await Future<void>.delayed(Duration.zero);
      expect(ex.pending!.title, contains('Delete transaction: Big Snack'));
      expect(ex.pending!.isDestructive, isTrue);
      await ex.confirm();

      expect(ledger.allTransactions.where((t) => t.id == 't_edit'), isEmpty);
    });
  });

  group('account resolution and edit guards', () {
    FinancialAccount card(String id, String name) => FinancialAccount(
          id: id,
          name: name,
          category: AccountCategory.creditCard,
          balance: 500,
          creditLimit: 10000,
          colorHex: '#FFFFFF',
          icon: 'card',
        );

    Future<(FinanceActionsExecutor, LedgerPresenter)> build(
        List<TransactionRecord> txns) async {
      final storage = MockStorageService();
      final stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => [
            card('gold', 'BPI Gold'),
            card('rewards', 'BPI Rewards'),
            _acc('mari', 'MariBank'),
          ]);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadTransactions()).thenAnswer((_) async => txns);
      when(storage.loadInstallments()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());
      final ledger = LedgerPresenter(storage, stats);
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return (FinanceActionsExecutor(bills: bills, ledger: ledger), ledger);
    }

    test('payCredit refuses an ambiguous card instead of picking one',
        () async {
      final (ex, _) = await build(const []);
      final result = await ex.propose(call('payCredit',
          {'creditAccount': 'BPI', 'fromAccount': 'MariBank', 'amount': 850}));
      expect(result.ok, isFalse);
      expect(result.summary, contains('"BPI Gold"'));
      expect(ex.pending, isNull);
    });

    test('payCredit refuses an unknown card instead of the first one',
        () async {
      final (ex, _) = await build(const []);
      final result = await ex.propose(call('payCredit',
          {'creditAccount': 'BDO', 'fromAccount': 'MariBank', 'amount': 850}));
      expect(result.ok, isFalse);
      expect(ex.pending, isNull);
    });

    test('payCredit shows the accounts it resolved', () async {
      final (ex, _) = await build(const []);
      unawaited(exPropose(
          ex,
          call('payCredit', {
            'creditAccount': 'gold',
            'fromAccount': 'mari',
            'amount': 850
          })));
      await Future<void>.delayed(Duration.zero);
      final rows = {for (final d in ex.pending!.details) d.label: d.value};
      expect(rows['Payment to'], 'BPI Gold');
      expect(rows['Pay from'], 'MariBank');
    });

    test('an edit naming an unknown account is refused, not re-pointed',
        () async {
      final (ex, ledger) = await build([
        TransactionRecord(
          id: 't1',
          date: DateTime(2026, 9, 10),
          accountId: 'mari',
          categoryId: '',
          amount: 150,
          type: TransactionType.outflow,
          description: 'Snack',
          month: '2026-09',
        ),
      ]);
      final result = await ex.propose(
          call('editTransaction', {'id': 't1', 'account': 'Metrobank'}));
      expect(result.ok, isFalse);
      expect(ledger.allTransactions.single.accountId, 'mari');
    });

    test('changing the amount of one transfer leg is refused', () async {
      final (ex, _) = await build([
        TransactionRecord(
          id: 'leg-out',
          date: DateTime(2026, 9, 10),
          accountId: 'mari',
          categoryId: '__transfer__',
          amount: 1000,
          type: TransactionType.outflow,
          description: 'Card payment',
          month: '2026-09',
          transferGroupId: 'g1',
          transferToAccountId: 'gold',
        ),
      ]);
      final result = await ex
          .propose(call('editTransaction', {'id': 'leg-out', 'amount': 500}));
      expect(result.ok, isFalse);
      expect(result.summary, contains('transfer'));
    });
  });
}

Future<void> exPropose(FinanceActionsExecutor ex, AiToolCall c) async {
  await ex.propose(c);
}

/// Local `unawaited` so the test does not depend on dart:async's import.
void unawaited(Future<void> future) {}
