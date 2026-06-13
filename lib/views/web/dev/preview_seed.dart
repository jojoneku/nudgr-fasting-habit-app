import 'package:flutter/foundation.dart';

import '../../../models/finance/bill.dart';
import '../../../models/finance/budget.dart';
import '../../../models/finance/budgeted_expense.dart';
import '../../../models/finance/finance_category.dart';
import '../../../models/finance/financial_account.dart';
import '../../../models/finance/receivable.dart';
import '../../../models/finance/transaction_record.dart';
import '../../../services/storage_service.dart';
import '../../../utils/finance_format.dart';

/// Compile-time flag: pass `--dart-define=PREVIEW_SEED=true` to boot the web
/// companion into preview-seed mode.
const bool _kPreviewSeedFlag = bool.fromEnvironment('PREVIEW_SEED');

/// Whether the web companion should boot into the local **preview-seed** mode:
/// skip Google sign-in, seed a believable demo dataset into local storage, and
/// render the dashboard directly — so the UI can be reviewed and screenshotted
/// without a live Supabase session or real account data.
///
/// Gated on BOTH the dart-define AND [kDebugMode], so it can never be reached in
/// a release or profile build even if the define leaks into a deploy.
///
/// ```
/// flutter run -t lib/main_web.dart -d web-server \
///   --web-port 8090 --web-hostname localhost \
///   --dart-define=PREVIEW_SEED=true
/// ```
bool get previewSeedEnabled => _kPreviewSeedFlag && kDebugMode;

/// Seeds a self-contained demo treasury into [StorageService] for preview mode.
///
/// All data lives under the [userId] scope (set via `setUserId` before calling
/// [seedInto]), isolated from any real signed-in user's namespace. Writing is
/// idempotent — each `save*` call replaces the previous seed — so it is safe to
/// run on every boot. NOTHING here touches Supabase; preview mode never builds a
/// SyncService.
///
/// The figures mirror the Claude Design "Treasury Dashboard" reference
/// (`docs/design/treasury-web-reference/`): net position ≈ ₱107,077, liquid
/// ≈ ₱33,760, June income ₱46,500, budget ₱12,589 / ₱30,749 used.
abstract final class PreviewSeed {
  /// Dedicated namespace for seeded data — kept well away from real Google uids.
  static const String userId = 'preview-seed-user';

  static Future<void> seedInto(StorageService storage) async {
    final now = DateTime.now();
    final month = toMonthKey(now);

    // Day-of-month for fixed dates; N days ago for the rolling daily-spend chart.
    DateTime dom(int day) => DateTime(now.year, now.month, day);
    DateTime dAgo(int days) =>
        DateTime(now.year, now.month, now.day).subtract(Duration(days: days));

    await storage.saveFinanceCategories(_categories);
    await storage.saveAccounts(_accounts);
    await storage
        .saveTransactions(_transactions(month: month, dom: dom, dAgo: dAgo));
    await storage.saveBudgets(_budgets(month));
    await storage.saveBudgetedExpenses(_budgetedExpenses(month));
    await storage.saveBills(_bills(month: month, dom: dom));
    await storage.saveReceivables(_receivables(month: month, dom: dom));
  }

  // ── Categories ────────────────────────────────────────────────────────────
  static final List<FinanceCategory> _categories = [
    _cat('c_salary', 'Salary', CategoryType.income, '#22c55e', 'cash'),
    _cat('c_bills', 'Bills & Utilities', CategoryType.expense, '#3b82f6',
        'flash'),
    _cat('c_house', 'Household Expenses', CategoryType.expense, '#8b5cf6',
        'home'),
    _cat('c_food', 'Food & Drinks', CategoryType.expense, '#22c55e', 'food'),
    _cat('c_trans', 'Transportation', CategoryType.expense, '#f59e0b', 'car'),
    _cat('c_fun', 'Guilt-Free / Fun', CategoryType.expense, '#ec4899',
        'party-popper'),
    _cat('c_health', 'Health & Wellness', CategoryType.expense, '#14b8a6',
        'heart-pulse'),
    _cat('c_net', 'Internet', CategoryType.expense, '#64748b', 'wifi'),
  ];

  static FinanceCategory _cat(
          String id, String name, CategoryType type, String hex, String icon) =>
      FinanceCategory(
          id: id, name: name, type: type, colorHex: hex, icon: icon);

  // ── Accounts ──────────────────────────────────────────────────────────────
  // Liquid total ≈ ₱33,760; assets ≈ ₱117,260; net worth ≈ ₱107,077 after the
  // ₱10,183 owed on the credit card (limit 54,690 ⇒ ₱44,507 available).
  static final List<FinancialAccount> _accounts = [
    _acc('a_bpi', 'BPI Personal', AccountCategory.bank, 24990.71, '#e11d48',
        'bank'),
    _acc('a_gcash', 'GCASH', AccountCategory.ewallet, 279.41, '#2563eb',
        'wallet'),
    _acc('a_maya', 'MAYA', AccountCategory.ewallet, 0, '#16a34a', 'wallet'),
    _acc('a_cash', 'CASH', AccountCategory.cash, 1178.00, '#64748b', 'cash'),
    _acc('a_mari', 'Maribank', AccountCategory.bank, 0, '#f59e0b', 'bank'),
    _acc(
        'a_gotyme', 'GoTyme', AccountCategory.bank, 3021.00, '#0ea5e9', 'bank'),
    _acc('a_vybe', 'BPI Vybe', AccountCategory.ewallet, 4291.57, '#a855f7',
        'wallet'),
    // Locked, top-level so each counts toward total assets.
    FinancialAccount(
      id: 'a_ef',
      name: 'Emergency Fund',
      category: AccountCategory.goal,
      balance: 42500,
      goalTarget: 180000,
      colorHex: '#22c55e',
      icon: 'shield-check',
    ),
    _acc('a_save', 'Maya Savings', AccountCategory.savings, 8000, '#10b981',
        'piggy-bank'),
    _acc('a_td', 'Time Deposit', AccountCategory.timeDeposit, 33000, '#0d9488',
        'lock'),
    // Liability: balance = amount owed.
    FinancialAccount(
      id: 'a_cc',
      name: 'BPI Credit Card',
      category: AccountCategory.creditCard,
      balance: 10183,
      creditLimit: 54690.27,
      statementDay: 5,
      paymentDueDay: 25,
      colorHex: '#dc2626',
      icon: 'credit-card',
    ),
  ];

  static FinancialAccount _acc(String id, String name, AccountCategory cat,
          double balance, String hex, String icon) =>
      FinancialAccount(
          id: id,
          name: name,
          category: cat,
          balance: balance,
          colorHex: hex,
          icon: icon);

  // ── Transactions ────────────────────────────────────────────────────────────
  static List<TransactionRecord> _transactions({
    required String month,
    required DateTime Function(int) dom,
    required DateTime Function(int) dAgo,
  }) {
    TransactionRecord txn(String id, double amount, TransactionType type,
            String accountId, String categoryId, DateTime date,
            {String? transferGroupId}) =>
        TransactionRecord(
          id: id,
          date: date,
          accountId: accountId,
          categoryId: categoryId,
          amount: amount,
          type: type,
          description: id,
          month: month,
          transferGroupId: transferGroupId,
        );

    return [
      // Income: ₱46,500 salary.
      txn('t_salary', 46500, TransactionType.inflow, 'a_bpi', 'c_salary',
          dom(1)),
      // ₱5,000 moved into savings — a locked inflow leg (transferGroupId set), so
      // it's excluded from income/expense totals but counts as a savings
      // contribution ⇒ savings rate ≈ 10.8%.
      txn('t_save', 5000, TransactionType.inflow, 'a_save', 'c_salary', dom(2),
          transferGroupId: 'g_save'),
      // Expenses — total ₱12,589, matching budget spent and the donut ranking.
      txn('t_house', 7997, TransactionType.outflow, 'a_bpi', 'c_house', dom(3)),
      txn('t_bills', 2738, TransactionType.outflow, 'a_bpi', 'c_bills', dom(5)),
      // Recent small spends drive the last-7-days chart.
      txn('t_health', 774, TransactionType.outflow, 'a_gcash', 'c_health',
          dAgo(6)),
      txn('t_food1', 320, TransactionType.outflow, 'a_gcash', 'c_food',
          dAgo(5)),
      txn('t_trans1', 150, TransactionType.outflow, 'a_cash', 'c_trans',
          dAgo(4)),
      txn('t_food2', 210, TransactionType.outflow, 'a_gcash', 'c_food',
          dAgo(3)),
      txn('t_trans2', 126, TransactionType.outflow, 'a_cash', 'c_trans',
          dAgo(2)),
      txn('t_food3', 274, TransactionType.outflow, 'a_gcash', 'c_food',
          dAgo(1)),
    ];
  }

  // ── Budgets (allocation + group) ────────────────────────────────────────────
  static List<Budget> _budgets(String month) {
    Budget b(String id, String catId, BudgetGroup group, double alloc) =>
        Budget(
            id: id,
            categoryId: catId,
            month: month,
            allocatedAmount: alloc,
            group: group,
            budgetType: BudgetType.monthly);

    return [
      b('b_bills', 'c_bills', BudgetGroup.nonNegotiables, 10000),
      b('b_net', 'c_net', BudgetGroup.nonNegotiables, 249),
      b('b_house', 'c_house', BudgetGroup.livingExpense, 14000),
      b('b_food', 'c_food', BudgetGroup.livingExpense, 2500),
      b('b_trans', 'c_trans', BudgetGroup.variableOptional, 1000),
      b('b_fun', 'c_fun', BudgetGroup.variableOptional, 2000),
      b('b_health', 'c_health', BudgetGroup.variableOptional, 1000),
    ];
  }

  // ── Budgeted expenses (spent) ────────────────────────────────────────────────
  static List<BudgetedExpense> _budgetedExpenses(String month) {
    BudgetedExpense e(
            String id, String name, String catId, double alloc, double spent) =>
        BudgetedExpense(
          id: id,
          name: name,
          budgetedType: BillType.other,
          month: month,
          allocatedAmount: alloc,
          spentAmount: spent,
          categoryId: catId,
        );

    return [
      e('be_bills', 'Bills & Utilities', 'c_bills', 10000, 2738),
      e('be_net', 'Internet', 'c_net', 249, 0),
      e('be_house', 'Household Expenses', 'c_house', 14000, 7997),
      e('be_food', 'Food & Drinks', 'c_food', 2500, 804),
      e('be_trans', 'Transportation', 'c_trans', 1000, 276),
      e('be_fun', 'Guilt-Free / Fun', 'c_fun', 2000, 0),
      e('be_health', 'Health & Wellness', 'c_health', 1000, 774),
    ];
  }

  // ── Bills & receivables ──────────────────────────────────────────────────────
  static List<Bill> _bills(
          {required String month, required DateTime Function(int) dom}) =>
      [
        Bill(
          id: 'bill_elec',
          name: 'Electricity',
          billType: BillType.utility,
          amount: 2500,
          dueDay: 15,
          month: month,
          categoryId: 'c_bills',
          accountId: 'a_bpi',
        ),
        Bill(
          id: 'bill_net',
          name: 'Internet',
          billType: BillType.subscription,
          amount: 1699,
          dueDay: 20,
          month: month,
          categoryId: 'c_net',
          accountId: 'a_bpi',
        ),
      ];

  static List<Receivable> _receivables(
          {required String month, required DateTime Function(int) dom}) =>
      [
        Receivable(
          id: 'rcv_reimb',
          name: 'Reimbursement',
          receivableType: ReceivableType.reimbursement,
          amount: 1128,
          expectedDate: dom(20),
          month: month,
          categoryId: 'c_salary',
          accountId: 'a_bpi',
        ),
      ];
}
