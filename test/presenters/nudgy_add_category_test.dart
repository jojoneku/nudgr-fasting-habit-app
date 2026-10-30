import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 4 parity: add a category from chat through the category
/// sheet's own save, and use it in a later row of the same batch.

FinanceCategory _cat(String id, String name,
        {CategoryType type = CategoryType.expense}) =>
    FinanceCategory(
      id: id,
      name: name,
      type: type,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

AiToolCall _call(String id, String name, Map<String, Object?> input) =>
    AiToolCall(id: id, name: name, input: input);

AiToolCall _addCat(String name,
        {String type = 'expense', bool? exclude, String id = 'c1'}) =>
    _call(id, 'addCategory', {
      'name': name,
      'type': type,
      if (exclude != null) 'excludeFromTotals': exclude,
    });

AiToolCall _addBill(String category, {String id = 'b1'}) =>
    _call(id, 'addBill', {
      'name': 'Vet',
      'amount': 1500,
      'dueDay': 20,
      'category': category,
    });

void main() {
  late MockBillsReceivablesPresenter bills;
  late MockStorageService storage;
  late LedgerPresenter ledger;
  late FinanceActionsExecutor ex;
  late List<Installment> savedPlans;

  setUp(() async {
    bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn('2026-09');
    when(bills.allBills).thenReturn([]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([]);
    when(bills.addBill(any, applyToFuture: anyNamed('applyToFuture')))
        .thenAnswer((_) async {});
    storage = MockStorageService();
    final stats = MockStatsPresenter();
    savedPlans = [];
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'spl',
            name: 'SPayLater',
            category: AccountCategory.bnpl,
            balance: 0,
            creditLimit: 50000,
            colorHex: '#FFFFFF',
            icon: 'card',
          ),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          _cat('food', 'Food'),
          _cat('petfood', 'Pet Food'),
          _cat('salary', 'Salary', type: CategoryType.income),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => savedPlans);
    when(storage.saveInstallments(any)).thenAnswer((inv) async {
      savedPlans =
          List<Installment>.from(inv.positionalArguments.first as List);
    });
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    while (ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    ex = FinanceActionsExecutor(bills: bills, ledger: ledger);
  });

  Map<String, String> rows(int index) =>
      {for (final d in ex.batch!.actions[index].details) d.label: d.value};

  FinanceCategory? saved(String name) =>
      ledger.categories.where((c) => c.name == name).firstOrNull;

  Bill savedBill() => verify(
          bills.addBill(captureAny, applyToFuture: anyNamed('applyToFuture')))
      .captured
      .single as Bill;

  /// Proposes [c] and expects it refused before any row.
  Future<String> refused(AiToolCall c) async {
    final r = await ex.propose(c);
    expect(r.ok, isFalse);
    expect(ex.batch, isNull);
    return r.summary;
  }

  test('the catalogue declares addCategory as a create', () {
    expect(financeToolNamed('addCategory')!.kind, AiToolKind.create);
  });

  test('the row shows what is saved, through the sheet\'s own values',
      () async {
    final result =
        ex.propose(_addCat('Reimbursement', type: 'income', exclude: true));
    await Future<void>.delayed(Duration.zero);
    expect(ex.pending!.tier, ProposalTier.create);
    expect(ex.pending!.title, 'Add category: Reimbursement');
    expect(rows(0), {
      'Name': 'Reimbursement',
      'Type': 'Income',
      'In totals': 'No — left out of totals and budget spend',
    });
    await ex.approveAll();
    final r = await result;

    expect(r.ok, isTrue);
    expect(r.summary, contains('"Reimbursement"'));
    final c = saved('Reimbursement')!;
    expect(c.type, CategoryType.income);
    expect(c.excludeFromTotals, isTrue);
    expect(c.icon, kAutoCategoryIconKey);
  });

  test('an expense category counts in totals by default', () async {
    final result = ex.propose(_addCat('Pets'));
    await Future<void>.delayed(Duration.zero);
    expect(rows(0)['In totals'], 'Yes');
    await ex.approveAll();
    expect((await result).ok, isTrue);
    expect(saved('Pets')!.type, CategoryType.expense);
    expect(saved('Pets')!.excludeFromTotals, isFalse);
  });

  group('refused before any row', () {
    test('a name that exists in another letter case, naming it', () async {
      final why = await refused(_addCat('food'));
      expect(why, contains('"Food" already exists'));
      expect(ledger.categories.where((c) => c.name.toLowerCase() == 'food'),
          hasLength(1));
    });

    test('the same name twice in one list', () async {
      final results = await Future.wait([
        ex.proposeBatch([_addCat('Pets'), _addCat('pets', id: 'c2')]),
        Future<void>.delayed(Duration.zero).then((_) => ex.decline()),
      ]);
      final answers = results.first as List<AiToolResult>;
      expect(answers.last.ok, isFalse);
      expect(answers.last.summary, contains('already added earlier'));
    });

    test('a type that is not expense or income', () async {
      final why = await refused(_addCat('Pets', type: 'transfer'));
      expect(why, contains('"expense" or "income"'));
    });

    test('an empty name', () async {
      expect(await refused(_addCat('  ')), contains('needs a name'));
    });
  });

  test('an unknown category name points the model at addCategory', () async {
    final why = await refused(_addBill('Pets'));
    expect(why, contains('No category is named "Pets"'));
    expect(why, contains('call addCategory'));
  });

  group('used in a later row of the same batch', () {
    test('the row shows the new category and saves its id', () async {
      final answers = ex.proposeBatch([_addCat('Pets'), _addBill('Pets')]);
      await Future<void>.delayed(Duration.zero);
      expect(ex.batch!.actions, hasLength(2));
      expect(rows(1)['Category'], 'Pets (new, added in this list)');

      await ex.approveAll();
      final r = await answers;
      expect(r.every((a) => a.ok), isTrue, reason: '$r');
      expect(savedBill().categoryId, saved('Pets')!.id);
    });

    test('an in-place edit of the later row keeps the new category', () async {
      final answers = ex.proposeBatch([_addCat('Pets'), _addBill('Pets')]);
      await Future<void>.delayed(Duration.zero);
      expect(ex.editAction('b1', {'name': 'Vet visit'}), isNull);
      expect(rows(1)['Category'], 'Pets (new, added in this list)');

      await ex.approveAll();
      await answers;
      final bill = savedBill();
      expect(bill.name, 'Vet visit');
      expect(bill.categoryId, saved('Pets')!.id);
    });

    test('a new name is never bound to a longer saved name', () async {
      // "Pet" is a prefix of the saved "Pet Food"; the row and the save
      // both mean the new "Pet".
      final answers = ex.proposeBatch([_addCat('Pet'), _addBill('pet')]);
      await Future<void>.delayed(Duration.zero);
      expect(rows(1)['Category'], 'Pet (new, added in this list)');

      await ex.approveAll();
      await answers;
      final categoryId = savedBill().categoryId;
      expect(categoryId, saved('Pet')!.id);
      expect(categoryId, isNot('petfood'));
    });

    test('a row before the addCategory row is refused', () async {
      final answers = ex.proposeBatch([_addBill('Pets'), _addCat('Pets')]);
      await Future<void>.delayed(Duration.zero);
      expect(ex.batch!.actions.single.call.name, 'addCategory');
      ex.decline();
      final r = await answers;
      expect(r.first.ok, isFalse);
      expect(r.first.summary, contains('BEFORE the rows that use it'));
    });

    test('removing the addCategory row removes the rows that use it', () async {
      final answers = ex.proposeBatch([
        _addCat('Pets'),
        _addBill('Pets'),
        _addBill('Food', id: 'b2'),
      ]);
      await Future<void>.delayed(Duration.zero);
      ex.removeAction('c1');
      expect([for (final a in ex.batch!.actions) a.call.id], ['b2']);

      await ex.approveAll();
      final r = await answers;
      expect(r[0].ok, isFalse);
      expect(r[1].ok, isFalse);
      expect(r[1].summary, contains('new category "Pets"'));
      expect(r[2].ok, isTrue);
      expect(savedBill().categoryId, 'food');
      expect(saved('Pets'), isNull);
    });

    test('an installment saves the new category', () async {
      final answers = ex.proposeBatch([
        _addCat('Gadgets'),
        _call('i1', 'addInstallment', {
          'name': 'Phone',
          'amount': 12000,
          'months': 6,
          'account': 'SPayLater',
          'category': 'Gadgets',
        }),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(rows(1)['Category'], 'Gadgets (new, added in this list)');

      await ex.approveAll();
      final r = await answers;
      expect(r.every((a) => a.ok), isTrue, reason: '$r');
      expect(savedPlans.single.categoryId, saved('Gadgets')!.id);
    });

    test('logged entries wait for the next step, with the reason', () async {
      final answers = ex.proposeBatch([
        _addCat('Pets'),
        _call('l1', 'logTransactions', {
          'entries': [
            {
              'description': 'Vet',
              'amount': 900,
              'type': 'outflow',
              'category': 'Pets',
            },
          ],
        }),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(ex.batchHasLedgerRows, isFalse);
      expect(ex.batch!.actions.single.call.name, 'addCategory');

      await ex.approveAll();
      final r = await answers;
      expect(r.first.ok, isTrue);
      expect(r.last.ok, isFalse);
      expect(r.last.summary, contains('in the next step'));
      expect(saved('Pets'), isNotNull);
    });
  });
}
