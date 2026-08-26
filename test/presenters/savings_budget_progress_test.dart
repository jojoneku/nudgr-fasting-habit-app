import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

/// What a savings budget row measures.
///
/// It used to be net movement: inflows minus outflows. Spend a fund on the very
/// thing it exists for — pay the dentist out of the Braces fund — and the row
/// went negative, dragged the month's total spent down with it, and left the
/// forecast reserving money that had already moved. Progress now counts what
/// was funded IN; the withdrawal is reported beside it rather than netted away.

String get _month => toMonthKey(DateTime.now());

FinancialAccount _account(
  String id, {
  AccountCategory category = AccountCategory.savings,
}) =>
    FinancialAccount(
      id: id,
      name: id,
      category: category,
      balance: 0,
      colorHex: '#46BD6B',
      icon: 'savings',
    );

TransactionRecord _txn({
  required String id,
  required String accountId,
  required double amount,
  required TransactionType type,
  String categoryId = 'cat',
  String? transferGroupId,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime.parse('$_month-15'),
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      description: id,
      month: _month,
      transferGroupId: transferGroupId,
    );

Budget _savingsBudget(String accountId, double amount) => Budget(
      id: 'b_$accountId',
      categoryId: accountId,
      month: _month,
      allocatedAmount: amount,
      group: BudgetGroupDef.idSavings,
      budgetType: BudgetType.monthly,
    );

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;

  void stub({
    List<Budget> budgets = const [],
    List<FinancialAccount> accounts = const [],
    List<TransactionRecord> transactions = const [],
    List<BudgetGroupDef> groups = const [],
  }) {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => groups);
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => <FinanceCategory>[]);
    when(storage.loadTransactions()).thenAnswer((_) async => transactions);
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.saveBudgets(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  }

  Future<BudgetPresenter> budgetPresenter() async {
    final p = BudgetPresenter(storage, stats, null, notifications);
    await p.load();
    return p;
  }

  /// The reported case: ₱3,000 funded into Braces, ₱1,800 of it spent on brace
  /// prep during the same month.
  void stubBracesMonth({double allocated = 3000}) => stub(
        accounts: [_account('braces')],
        budgets: [_savingsBudget('braces', allocated)],
        transactions: [
          _txn(
            id: 'fund',
            accountId: 'braces',
            amount: 3000,
            type: TransactionType.inflow,
          ),
          _txn(
            id: 'dentist',
            accountId: 'braces',
            amount: 1800,
            type: TransactionType.outflow,
          ),
        ],
      );

  group('spending a fund on its purpose', () {
    test('does not read as negative progress', () async {
      stubBracesMonth();
      final p = await budgetPresenter();

      expect(p.fundedInto('braces'), 3000, reason: 'the funding still counts');
      expect(p.withdrawnFrom('braces'), 1800);
      // The old net figure was 1200, which read as 40% of a goal actually met.
      expect(p.spentFor('braces'), 3000);
      expect(p.remainingFor('braces'), 0);
      expect(p.sectionSpent(BudgetGroupDef.idSavings), 3000);
    });

    test('cannot drag the month total below zero', () async {
      // Withdraw more than was funded — the pathological version of the report.
      stub(
        accounts: [_account('braces')],
        budgets: [_savingsBudget('braces', 3000)],
        transactions: [
          _txn(
            id: 'dentist',
            accountId: 'braces',
            amount: 5000,
            type: TransactionType.outflow,
          ),
        ],
      );
      final p = await budgetPresenter();

      expect(p.fundedInto('braces'), 0);
      expect(p.withdrawnFrom('braces'), 5000);
      expect(p.totalSpent, 0, reason: 'was −5000, corrupting % used');
      expect(p.percentUsed, 0);
    });

    test('the withdrawal survives into the row view-models', () async {
      stubBracesMonth();
      final p = await budgetPresenter();

      final webRow = p.budgetRows.firstWhere((r) => r.targetId == 'braces');
      expect(webRow.spent, 3000);
      expect(webRow.withdrawn, 1800);
      expect(webRow.progress, 1.0);
      expect(webRow.isOver, isFalse);

      final section = p.budgetSections
          .firstWhere((s) => s.groupId == BudgetGroupDef.idSavings);
      final mobileRow = section.rows.firstWhere((r) => r.targetId == 'braces');
      expect(mobileRow.actual, 3000);
      expect(mobileRow.withdrawn, 1800);
      expect(mobileRow.met, isTrue);
    });
  });

  group('a transfer between two funds', () {
    test('funds neither side', () async {
      stub(
        accounts: [
          _account('braces'),
          _account('travel', category: AccountCategory.goal),
        ],
        budgets: [
          _savingsBudget('braces', 3000),
          _savingsBudget('travel', 3000),
        ],
        transactions: [
          _txn(
            id: 'out',
            accountId: 'braces',
            amount: 3000,
            type: TransactionType.outflow,
            transferGroupId: 'g1',
          ),
          _txn(
            id: 'in',
            accountId: 'travel',
            amount: 3000,
            type: TransactionType.inflow,
            transferGroupId: 'g1',
          ),
        ],
      );
      final p = await budgetPresenter();

      expect(p.fundedInto('travel'), 0,
          reason: 'the destination must not inflate');
      expect(p.fundedInto('braces'), 0);
      expect(p.sectionSpent(BudgetGroupDef.idSavings), 0);
      // The money did leave Braces, and the row says so.
      expect(p.withdrawnFrom('braces'), 3000);
    });

    test('a transfer in from a spending account does fund the goal', () async {
      stub(
        accounts: [
          _account('gcash', category: AccountCategory.ewallet),
          _account('travel', category: AccountCategory.goal),
        ],
        budgets: [_savingsBudget('travel', 3000)],
        transactions: [
          _txn(
            id: 'out',
            accountId: 'gcash',
            amount: 3000,
            type: TransactionType.outflow,
            transferGroupId: 'g1',
          ),
          _txn(
            id: 'in',
            accountId: 'travel',
            amount: 3000,
            type: TransactionType.inflow,
            transferGroupId: 'g1',
          ),
        ],
      );
      final p = await budgetPresenter();

      expect(p.fundedInto('travel'), 3000);
      expect(p.withdrawnFrom('travel'), 0);
    });
  });

  group('section totals', () {
    test('a user-created savings group reports only its own rows', () async {
      stub(
        groups: [
          const BudgetGroupDef(
            id: 'sinking',
            name: 'Sinking Funds',
            isSavings: true,
            isBuiltIn: false,
            sortOrder: 3,
          ),
        ],
        accounts: [_account('braces'), _account('ef')],
        budgets: [
          _savingsBudget('ef', 5000),
          Budget(
            id: 'b_braces',
            categoryId: 'braces',
            month: _month,
            allocatedAmount: 3000,
            group: 'sinking',
            budgetType: BudgetType.monthly,
          ),
        ],
        transactions: [
          _txn(
            id: 'fund_ef',
            accountId: 'ef',
            amount: 5000,
            type: TransactionType.inflow,
          ),
          _txn(
            id: 'fund_braces',
            accountId: 'braces',
            amount: 3000,
            type: TransactionType.inflow,
          ),
        ],
      );
      final p = await budgetPresenter();

      // Each savings group used to report every savings row, so both sections
      // claimed the full 8000 against their own smaller allocation.
      expect(p.sectionSpent(BudgetGroupDef.idSavings), 5000);
      expect(p.sectionSpent('sinking'), 3000);
      expect(p.sectionAllocated(BudgetGroupDef.idSavings), 5000);
      expect(p.sectionAllocated('sinking'), 3000);
    });
  });

  group('the cash forecast', () {
    test('stops reserving money already moved into the fund', () async {
      stubBracesMonth();
      when(storage.loadBills()).thenAnswer((_) async => []);
      when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(storage.loadReceivables()).thenAnswer((_) async => []);
      when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);

      final dash = TreasuryDashboardPresenter(storage);
      await dash.load();

      // Net math read 1200 spent against a 3000 budget, leaving 1800 still
      // "to set aside" — deducted from projected cash on top of the 1800 the
      // withdrawal had already taken out.
      expect(dash.totalBudgetSpent, 3000);
      expect(dash.totalBudgetRemaining, 0);
    });
  });
}
