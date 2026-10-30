import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 4 parity: edit an account from chat through the account
/// sheet's own save, with the row showing before → after for exactly the
/// fields that are saved.

final _nextYear = DateTime.now().year + 1;

List<FinancialAccount> _accounts() => [
      FinancialAccount(
        id: 'bpi',
        name: 'BPI',
        category: AccountCategory.bank,
        balance: 8000,
        colorHex: '#FFFFFF',
        icon: 'bank',
      ),
      FinancialAccount(
        id: 'gold',
        name: 'BPI Gold',
        category: AccountCategory.creditCard,
        balance: 4200,
        creditLimit: 20000,
        statementDay: 10,
        dueDaysAfterStatement: 15,
        colorHex: '#FFFFFF',
        icon: 'card',
      ),
      FinancialAccount(
        id: 'braces',
        name: 'Braces',
        category: AccountCategory.goal,
        parentAccountId: 'bpi',
        balance: 12000,
        goalTarget: 50000,
        colorHex: '#FFFFFF',
        icon: 'goal',
      ),
      FinancialAccount(
        id: 'td',
        name: 'Time Deposit',
        category: AccountCategory.timeDeposit,
        parentAccountId: 'bpi',
        balance: 100000,
        maturityDate: DateTime(_nextYear, 1, 15),
        colorHex: '#FFFFFF',
        icon: 'td',
      ),
    ];

AiToolCall _edit(Map<String, Object?> input) =>
    AiToolCall(id: 'e1', name: 'editAccount', input: input);

void main() {
  late FinanceActionsExecutor ex;
  late LedgerPresenter ledger;
  late MockStorageService storage;
  List<FinancialAccount>? saved;

  setUp(() async {
    saved = null;
    final bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn('2026-09');
    when(bills.allBills).thenReturn([]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([]);
    storage = MockStorageService();
    final stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    // Storage keeps what was saved, so a reload reads the write back.
    when(storage.loadAccounts()).thenAnswer((_) async => saved ?? _accounts());
    when(storage.saveAccounts(any)).thenAnswer((inv) async {
      saved = List.of(inv.positionalArguments.first as List<FinancialAccount>);
    });
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgets()).thenAnswer((_) async => []);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(stats.stats).thenReturn(UserStats.initial());
    ledger = LedgerPresenter(storage, stats);
    while (ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final dashboard = TreasuryDashboardPresenter(storage, ledger);
    while (dashboard.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    ex = FinanceActionsExecutor(
        bills: bills, ledger: ledger, dashboard: dashboard);
  });

  Map<String, String> rows() =>
      {for (final d in ex.pending!.details) d.label: d.value};

  FinancialAccount savedAccount(String id) =>
      saved!.firstWhere((a) => a.id == id);

  /// Shows [c], approves it and returns its result.
  Future<AiToolResult> approve(AiToolCall c) async {
    final result = ex.propose(c);
    await Future<void>.delayed(Duration.zero);
    expect(ex.pending, isNotNull, reason: 'the row should be shown');
    await ex.approveAll();
    return result;
  }

  /// Proposes [c] and expects it refused before any row, with nothing saved.
  Future<String> refused(AiToolCall c) async {
    final r = await ex.propose(c);
    expect(r.ok, isFalse);
    expect(ex.batch, isNull);
    expect(saved, isNull);
    return r.summary;
  }

  test('the catalogue declares editAccount as an update without a balance', () {
    final tool = financeToolNamed('editAccount')!;
    expect(tool.kind, AiToolKind.update);
    final props = (tool.inputSchema['properties'] as Map).keys;
    expect(props, isNot(contains('balance')));
    expect(props, isNot(contains('category')));
  });

  test('a credit edit shows before → after and saves exactly that', () async {
    final c = _edit({
      'id': 'gold',
      'creditLimit': 30000,
      'statementDay': 12,
      'paymentDueDay': 5,
    });
    ex.propose(c).ignore();
    await Future<void>.delayed(Duration.zero);
    expect(ex.pending!.tier, ProposalTier.change);
    expect(ex.pending!.title, 'Update account: BPI Gold');
    expect(rows(), {
      'Credit limit': '₱20000 → ₱30000',
      'Statement day': 'day 10 → day 12',
      // The fixed day replaces the "days after" rule, as on the sheet.
      'Payment due': '15 days after the statement → day 5',
    });
    ex.decline();

    final r = await approve(_edit({
      'id': 'gold',
      'creditLimit': 30000,
      'statementDay': 12,
      'paymentDueDay': 5,
    }));
    expect(r.ok, isTrue);
    final a = savedAccount('gold');
    expect(a.creditLimit, 30000);
    expect(a.statementDay, 12);
    expect(a.paymentDueDay, 5);
    expect(a.dueDaysAfterStatement, isNull);
    expect(a.balance, 4200, reason: 'a balance never moves by an edit');
    expect(a.name, 'BPI Gold');
    expect(
        ledger.accounts.firstWhere((a) => a.id == 'gold').creditLimit, 30000);
    expect(r.summary, contains('Credit limit ₱20000 → ₱30000'));
  });

  test('a field equal to its current value gets no row and no change',
      () async {
    ex
        .propose(
            _edit({'id': 'gold', 'creditLimit': 20000, 'statementDay': 12}))
        .ignore();
    await Future<void>.delayed(Duration.zero);
    expect(rows(), {'Statement day': 'day 10 → day 12'});
  });

  test('a goal rename and target saves both, keeping the parent', () async {
    final r = await approve(
        _edit({'id': 'braces', 'name': 'Braces Fund', 'goalTarget': 60000}));
    expect(r.ok, isTrue);
    final a = savedAccount('braces');
    expect(a.name, 'Braces Fund');
    expect(a.goalTarget, 60000);
    expect(a.parentAccountId, 'bpi');
    expect(a.balance, 12000);
  });

  test('a rename row shows the old and new name', () async {
    ex.propose(_edit({'id': 'braces', 'name': 'Braces Fund'})).ignore();
    await Future<void>.delayed(Duration.zero);
    expect(rows(), {'Name': 'Braces → Braces Fund'});
  });

  test('a maturity date moves on a time deposit', () async {
    ex
        .propose(_edit({'id': 'td', 'maturityDate': '$_nextYear-03-01'}))
        .ignore();
    await Future<void>.delayed(Duration.zero);
    expect(rows(), {'Maturity date': '$_nextYear-01-15 → $_nextYear-03-01'});
    ex.decline();

    final r =
        await approve(_edit({'id': 'td', 'maturityDate': '$_nextYear-03-01'}));
    expect(r.ok, isTrue);
    expect(savedAccount('td').maturityDate, DateTime(_nextYear, 3, 1));
  });

  group('refused before any row', () {
    test('an id that find never returned', () async {
      final why = await refused(_edit({'id': 'nope', 'name': 'X'}));
      expect(why, contains('No account has the id "nope"'));
      expect(why, contains('find (entity account)'));
    });

    test('a balance', () async {
      final why = await refused(_edit({'id': 'bpi', 'balance': 9000}));
      expect(why, contains('A balance never changes by an edit'));
    });

    test('a type change', () async {
      final why = await refused(_edit({'id': 'bpi', 'category': 'savings'}));
      expect(why, contains('type of an account cannot change'));
    });

    test('a credit limit on a bank account', () async {
      final why = await refused(_edit({'id': 'bpi', 'creditLimit': 5000}));
      expect(why, contains('"BPI" has no credit limit'));
    });

    test('a goal target on a credit card', () async {
      final why = await refused(_edit({'id': 'gold', 'goalTarget': 5000}));
      expect(why, contains('"BPI Gold" has no goal target'));
    });

    test('a statement day the sheet does not offer', () async {
      final why = await refused(_edit({'id': 'gold', 'statementDay': 31}));
      expect(why, contains('from 1 to 28'));
    });

    test('a maturity date in the past', () async {
      final why =
          await refused(_edit({'id': 'td', 'maturityDate': '2020-01-01'}));
      expect(why, contains('in the past'));
    });

    test('a call that changes nothing', () async {
      final why = await refused(_edit({'id': 'gold', 'creditLimit': 20000}));
      expect(why, contains('changes nothing'));
    });
  });

  test('without the account owner the edit is refused, not faked', () async {
    final bare = FinanceActionsExecutor(
        bills: MockBillsReceivablesPresenter(), ledger: ledger);
    final r = await bare.propose(_edit({'id': 'bpi', 'name': 'BPI Savings'}));
    expect(r.ok, isFalse);
    expect(r.summary, contains('not available'));
  });
}
