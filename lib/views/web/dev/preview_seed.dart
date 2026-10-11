import 'package:flutter/foundation.dart';

import '../../../models/finance/bill.dart';
import '../../../models/finance/budget.dart';
import '../../../models/finance/budget_group_def.dart';
import '../../../models/finance/budgeted_expense.dart';
import '../../../models/finance/finance_category.dart';
import '../../../models/finance/financial_account.dart';
import '../../../models/finance/installment.dart';
import '../../../models/finance/monthly_summary.dart';
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
/// The shapes mirror the owner's real treasury as drawn on the Treasury Web v2
/// canvas (`docs/design-reference/web-v2/`): 23 accounts (7 liquid, one of
/// them overdrawn; 8 goals; 7 credit lines; 1 investment), 11 bills for the
/// current month (4 unpaid), 2 receivables, 7 budgeted set-asides, 8
/// installment plans and 6 closed monthly summaries. Names are real, amounts
/// are illustrative. Every date is relative to `DateTime.now()` so the seed
/// stays "this month" whenever it is run.
abstract final class PreviewSeed {
  /// Dedicated namespace for seeded data — kept well away from real Google uids.
  static const String userId = 'preview-seed-user';

  static Future<void> seedInto(StorageService storage) async {
    final now = DateTime.now();
    final month = toMonthKey(now);
    final lastMonth = previousMonth(month);

    // Day-of-month for fixed dates; N days ago for the rolling daily-spend
    // chart; a settlement day clamped to today so nothing reads as paid in the
    // future when the preview runs early in the month.
    DateTime dom(int day) => DateTime(now.year, now.month, day);
    DateTime prevDom(int day) => DateTime(now.year, now.month - 1, day);
    DateTime dAgo(int days) =>
        DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
    DateTime paidOn(int day) => dom(day <= now.day ? day : now.day);

    await storage.saveFinanceCategories(_categories);
    await storage.saveAccounts(_accounts);
    await storage.saveTransactions(_transactions(
      month: month,
      lastMonth: lastMonth,
      dom: dom,
      prevDom: prevDom,
      dAgo: dAgo,
      paidOn: paidOn,
    ));
    await storage.saveBudgets(_budgets(month));
    await storage.saveBudgetedExpenses(_budgetedExpenses(month));
    await storage.saveBills(_bills(month: month, paidOn: paidOn));
    await storage
        .saveReceivables(_receivables(month: month, dom: dom, paidOn: paidOn));
    await storage.saveInstallments(
        _installments(month: month, dom: dom, prevDom: prevDom, dAgo: dAgo));
    await storage.saveMonthlySummaries(_monthlySummaries(month));
  }

  // ── Categories ────────────────────────────────────────────────────────────
  static final List<FinanceCategory> _categories = [
    // Income
    _cat('c_salary', 'Salary', CategoryType.income, '#22c55e', 'cash'),
    _cat('c_side', 'Side Income', CategoryType.income, '#10b981', 'briefcase'),
    // Money fronted and paid back — kept out of the headline Income figure.
    FinanceCategory(
      id: 'c_reimb',
      name: 'Reimbursement',
      type: CategoryType.income,
      colorHex: '#64748b',
      icon: 'cash-refund',
      excludeFromTotals: true,
    ),
    // Expense
    _cat('c_bills', 'Bills & Utilities', CategoryType.expense, '#3b82f6',
        'flash'),
    _cat('c_net', 'Internet', CategoryType.expense, '#64748b', 'wifi'),
    _cat('c_govt', 'Government Contributions', CategoryType.expense, '#0ea5e9',
        'shield-account'),
    _cat('c_insure', 'Insurance', CategoryType.expense, '#6366f1',
        'shield-check'),
    _cat('c_house', 'Household Expenses', CategoryType.expense, '#8b5cf6',
        'home'),
    _cat('c_grocery', 'Groceries', CategoryType.expense, '#84cc16', 'cart'),
    _cat('c_food', 'Food & Drinks', CategoryType.expense, '#22c55e', 'food'),
    _cat('c_trans', 'Transportation', CategoryType.expense, '#f59e0b', 'car'),
    _cat('c_fun', 'Guilt-Free / Fun', CategoryType.expense, '#ec4899',
        'party-popper'),
    _cat('c_health', 'Health & Wellness', CategoryType.expense, '#14b8a6',
        'heart-pulse'),
    _cat('c_braces', 'Braces', CategoryType.expense, '#f97316', 'tooth'),
    _cat('c_family', 'Family Support', CategoryType.expense, '#a855f7',
        'account-group'),
    _cat('c_shop', 'Shopping', CategoryType.expense, '#d946ef', 'shopping'),
    _cat('c_tech', 'Tech & Gadgets', CategoryType.expense, '#06b6d4', 'laptop'),
    _cat('c_edu', 'Education', CategoryType.expense, '#0284c7', 'school'),
    _cat('c_sub', 'Subscriptions', CategoryType.expense, '#7c3aed',
        'television-play'),
    _cat('c_ccpay', 'Credit Card Payment', CategoryType.expense, '#ef4444',
        'credit-card'),
    _cat('c_savings', 'Savings & Goals', CategoryType.expense, '#10b981',
        'piggy-bank'),
    // The reserved transfer category the ledger would otherwise create on
    // first use; seeded so the transfer legs below resolve to it.
    FinanceCategory.transfer(),
  ];

  static FinanceCategory _cat(
          String id, String name, CategoryType type, String hex, String icon) =>
      FinanceCategory(
          id: id, name: name, type: type, colorHex: hex, icon: icon);

  // ── Accounts ──────────────────────────────────────────────────────────────
  // Liquid ≈ ₱30,542.27 (Maribank overdrawn by ₱2,153.06); goals ₱39,350 of
  // ₱296,500; credit owed ₱18,852.04 across 4 of 7 lines (limits ₱285,000).
  static final List<FinancialAccount> _accounts = [
    // ── Liquid (7) ──
    _acc('a_bpi', 'BPI Savings', AccountCategory.bank, 25945.33, '#9B2C2C',
        'bank'),
    _acc('a_maya', 'MAYA', AccountCategory.ewallet, 6000, '#1B7A4B', 'wallet'),
    _acc('a_cash', 'CASH', AccountCategory.cash, 500, '#64748b', 'cash'),
    _acc('a_gcash', 'GCASH', AccountCategory.ewallet, 250, '#1565C0', 'wallet'),
    // Overdrawn: the last transfer out was larger than the balance. Exercises
    // the negative-balance paths on every page.
    _acc('a_mari', 'Maribank', AccountCategory.bank, -2153.06, '#2A2566',
        'bank'),
    _acc('a_gotyme', 'GoTyme', AccountCategory.bank, 0, '#0ea5e9', 'bank'),
    _acc('a_vybe', 'Vybe (BPI)', AccountCategory.ewallet, 0, '#a855f7',
        'wallet'),
    // ── Goals (8) — top-level so each counts toward total assets ──
    _goal('a_ef', 'Emergency Fund', 33850, 180000, '#22c55e', 'shield-check'),
    _goal('a_tuition', 'Tuition Fund', 3500, 20000, '#0284c7', 'school'),
    _goal('a_bday', 'Birthday Fund', 1500, 5000, '#ec4899', 'cake-variant'),
    _goal(
        'a_bracesm', 'Braces Maintenance Fund', 500, 5000, '#f97316', 'tooth'),
    _goal('a_bracess', 'Savings Braces Fund', 0, 60000, '#fb923c',
        'tooth-outline'),
    _goal('a_travel', 'Travel Fund', 0, 20000, '#14b8a6', 'airplane'),
    _goal('a_nice', 'Buy Something Nice Fund', 0, 5000, '#d946ef', 'gift'),
    _goal('a_motor', 'Motor Maintenance Fund', 0, 1500, '#64748b', 'motorbike'),
    // ── Credit (7) — balance = amount owed ──
    FinancialAccount(
      id: 'a_cc_bpi',
      name: 'Credit Card CC (BPI)',
      category: AccountCategory.creditCard,
      balance: 7684.79,
      creditLimit: 75000,
      statementDay: 20,
      paymentDueDay: 5,
      colorHex: '#9B2C2C',
      icon: 'credit-card',
    ),
    FinancialAccount(
      id: 'a_cc_mari',
      name: 'Credit Card (Maribank)',
      category: AccountCategory.creditCard,
      balance: 4786.35,
      creditLimit: 75000,
      colorHex: '#2A2566',
      icon: 'credit-card',
    ),
    FinancialAccount(
      id: 'a_cc_maya',
      name: 'Credit Card (Maya)',
      category: AccountCategory.creditCard,
      balance: 374.90,
      creditLimit: 10000,
      statementDay: 25,
      paymentDueDay: 10,
      colorHex: '#1B7A4B',
      icon: 'credit-card',
    ),
    FinancialAccount(
      id: 'a_cc_madness',
      name: 'Madness Limit (BPI)',
      category: AccountCategory.creditCard,
      balance: 0,
      creditLimit: 75000,
      colorHex: '#9B2C2C',
      icon: 'credit-card-outline',
    ),
    FinancialAccount(
      id: 'a_easy',
      name: 'Maya Easy Credit',
      category: AccountCategory.creditLine,
      balance: 6006,
      creditLimit: 10000,
      colorHex: '#1B7A4B',
      icon: 'credit-card-clock',
    ),
    FinancialAccount(
      id: 'a_mariloan',
      name: 'Maribank Loan',
      category: AccountCategory.creditLine,
      balance: 0,
      creditLimit: 40000,
      colorHex: '#2A2566',
      icon: 'hand-coin',
    ),
    FinancialAccount(
      id: 'a_shopee',
      name: 'ShopeePay',
      category: AccountCategory.bnpl,
      balance: 0,
      creditLimit: 75000,
      statementDay: 1,
      paymentDueDay: 15,
      colorHex: '#f97316',
      icon: 'shopping',
    ),
    // ── Investment (1) ──
    _acc('a_pagibig', 'Pagibig', AccountCategory.investment, 0, '#0d9488',
        'chart-line'),
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

  static FinancialAccount _goal(String id, String name, double balance,
          double target, String hex, String icon) =>
      FinancialAccount(
        id: id,
        name: name,
        category: AccountCategory.goal,
        balance: balance,
        goalTarget: target,
        colorHex: hex,
        icon: icon,
      );

  // ── Transactions ──────────────────────────────────────────────────────────
  static List<TransactionRecord> _transactions({
    required String month,
    required String lastMonth,
    required DateTime Function(int) dom,
    required DateTime Function(int) prevDom,
    required DateTime Function(int) dAgo,
    required DateTime Function(int) paidOn,
  }) {
    TransactionRecord txn(
      String id,
      String description,
      double amount,
      TransactionType type,
      String accountId,
      String categoryId,
      DateTime date, {
      String? note,
      String? billId,
      String? receivableId,
      String? installmentId,
      bool isInstallment = false,
    }) =>
        TransactionRecord(
          id: id,
          date: date,
          accountId: accountId,
          categoryId: categoryId,
          amount: amount,
          type: type,
          description: description,
          note: note,
          month: toMonthKey(date),
          billId: billId,
          receivableId: receivableId,
          installmentId: installmentId,
          isInstallment: isInstallment,
        );

    // A transfer is two legs sharing a group id, as the ledger writes them:
    // an outflow on the source pointing at the destination, and an inflow on
    // the destination pointing back. Both carry the reserved transfer category
    // so no spend/income aggregate counts them.
    List<TransactionRecord> transfer(
      String id,
      String description,
      double amount,
      String fromId,
      String toId,
      DateTime date, {
      String? billId,
    }) =>
        [
          TransactionRecord(
            id: '${id}_out',
            date: date,
            accountId: fromId,
            categoryId: FinanceCategory.transferCategoryId,
            amount: amount,
            type: TransactionType.outflow,
            description: description,
            month: toMonthKey(date),
            transferToAccountId: toId,
            transferGroupId: id,
            billId: billId,
          ),
          TransactionRecord(
            id: '${id}_in',
            date: date,
            accountId: toId,
            categoryId: FinanceCategory.transferCategoryId,
            amount: amount,
            type: TransactionType.inflow,
            description: description,
            month: toMonthKey(date),
            transferToAccountId: fromId,
            transferGroupId: id,
            billId: billId,
          ),
        ];

    return [
      // ── Last month: enough for the Ledger stepper and the live History
      //    comparisons to have a neighbour ──
      txn('t_lm_salary', 'Alphaus Salary', 47976.59, TransactionType.inflow,
          'a_bpi', 'c_salary', prevDom(7)),
      txn('t_lm_elec', 'Electricity', 1540, TransactionType.outflow, 'a_gcash',
          'c_bills', prevDom(16)),
      txn('t_lm_grocery', 'SM Supermarket', 2980, TransactionType.outflow,
          'a_bpi', 'c_grocery', prevDom(12)),
      txn('t_lm_brace', 'Brace Monthly', 4500, TransactionType.outflow,
          'a_maya', 'c_braces', prevDom(24)),
      txn('t_lm_fun', 'Movie night', 620, TransactionType.outflow, 'a_maya',
          'c_fun', prevDom(20)),

      // ── This month · income ──
      txn('t_salary', 'Alphaus Salary', 47976.59, TransactionType.inflow,
          'a_bpi', 'c_salary', paidOn(7),
          receivableId: 'rcv_salary'),

      // ── This month · paid bills (government contributions) ──
      txn('t_philhealth', 'Philhealth', 508, TransactionType.outflow, 'a_gcash',
          'c_govt', paidOn(8),
          billId: 'bill_philhealth'),
      txn('t_sss', 'SSS', 758, TransactionType.outflow, 'a_maya', 'c_govt',
          paidOn(8),
          billId: 'bill_sss'),
      txn('t_pagibig', 'Pag-Ibig Regular', 205, TransactionType.outflow,
          'a_maya', 'c_govt', paidOn(8),
          billId: 'bill_pagibig'),
      txn('t_mp2', 'Pag-Ibig MP2', 505, TransactionType.outflow, 'a_maya',
          'c_govt', paidOn(8),
          note: 'Voluntary savings program', billId: 'bill_mp2'),

      // ── This month · card statements paid (transfers into the card) ──
      ...transfer('g_pay_bpi', 'Credit Card CC (BPI) statement', 2522.97,
          'a_bpi', 'a_cc_bpi', paidOn(5),
          billId: 'bill_stmt_bpi'),
      ...transfer('g_pay_maya', 'Credit Card (Maya) statement', 5505.90,
          'a_bpi', 'a_cc_maya', paidOn(10),
          billId: 'bill_stmt_maya'),
      ...transfer('g_pay_shopee', 'ShopeePay statement', 2424.40, 'a_bpi',
          'a_shopee', paidOn(10),
          billId: 'bill_stmt_shopee'),

      // ── This month · the transfer that overdrew Maribank ──
      ...transfer(
          'g_mari', 'Maribank → MAYA', 3000, 'a_mari', 'a_maya', paidOn(2)),

      // ── This month · spending ──
      txn('t_grocery', 'SM Supermarket', 1850, TransactionType.outflow, 'a_bpi',
          'c_grocery', paidOn(3),
          note: 'Weekly groceries'),
      txn('t_house', 'Water refill + LPG', 1200, TransactionType.outflow,
          'a_maya', 'c_house', paidOn(4)),
      txn('t_fun', 'Dinner with friends', 450, TransactionType.outflow,
          'a_maya', 'c_fun', dAgo(4)),
      // Recent small spends drive the last-7-days chart.
      txn('t_health', 'Pharmacy', 774, TransactionType.outflow, 'a_gcash',
          'c_health', dAgo(6)),
      txn('t_food1', 'Lunch', 320, TransactionType.outflow, 'a_gcash', 'c_food',
          dAgo(5)),
      txn('t_trans1', 'Grab', 150, TransactionType.outflow, 'a_cash', 'c_trans',
          dAgo(5)),
      txn('t_food2', 'Coffee', 210, TransactionType.outflow, 'a_gcash',
          'c_food', dAgo(3)),
      txn('t_trans2', 'Jeep + MRT', 126, TransactionType.outflow, 'a_cash',
          'c_trans', dAgo(2)),
      txn('t_food3', 'Merienda', 274, TransactionType.outflow, 'a_gcash',
          'c_food', dAgo(1)),

      // ── Installment purchases on the card (hold credit, not cash spend) ──
      txn('t_inst_fridge', 'Panasonic Refrigerator', 25992,
          TransactionType.outflow, 'a_cc_bpi', 'c_house', paidOn(2),
          installmentId: 'inst_fridge', isInstallment: true),
      txn('t_inst_xiaomi', "Papa's Xiaomi Redmi Note 15", 11999,
          TransactionType.outflow, 'a_cc_bpi', 'c_tech', prevDom(28),
          installmentId: 'inst_xiaomi', isInstallment: true),
      txn('t_inst_bag', 'MENSPE Fashion Backpack', 627.48,
          TransactionType.outflow, 'a_cc_bpi', 'c_shop', dAgo(6),
          installmentId: 'inst_bag', isInstallment: true),
      txn('t_inst_cam', 'Xiaomi Camera C301', 898.86, TransactionType.outflow,
          'a_cc_bpi', 'c_tech', dAgo(6),
          installmentId: 'inst_cam', isInstallment: true),
      txn('t_inst_cable', 'Solar DC Cable', 1118.28, TransactionType.outflow,
          'a_cc_bpi', 'c_house', dAgo(5),
          installmentId: 'inst_cable', isInstallment: true),
      txn('t_inst_inv', 'Pure Sine Wave Inverter', 1703.37,
          TransactionType.outflow, 'a_cc_bpi', 'c_house', dAgo(5),
          installmentId: 'inst_inv', isInstallment: true),
      txn('t_inst_outlet', 'Extension Outlet', 139.38, TransactionType.outflow,
          'a_cc_bpi', 'c_house', dAgo(4),
          installmentId: 'inst_outlet', isInstallment: true),
      txn('t_inst_fuse', 'ANL Fuse Holder', 248.76, TransactionType.outflow,
          'a_cc_bpi', 'c_house', dAgo(4),
          installmentId: 'inst_fuse', isInstallment: true),
    ];
  }

  // ── Budgets (allocation + group) ────────────────────────────────────────────
  // Expense rows key on a category; savings rows key on the goal ACCOUNT id
  // (see BudgetPresenter.savingsBudgets) and sit in the built-in Savings group.
  static List<Budget> _budgets(String month) {
    Budget b(String id, String key, String group, double alloc,
            {BudgetType type = BudgetType.monthly}) =>
        Budget(
          id: id,
          categoryId: key,
          month: month,
          allocatedAmount: alloc,
          group: group,
          budgetType: type,
          seriesId: 'bs_$id',
        );

    const ess = BudgetGroupDef.idNonNegotiables;
    const vari = BudgetGroupDef.idVariableOptional;
    const sav = BudgetGroupDef.idSavings;
    return [
      b('b_bills', 'c_bills', ess, 2000),
      b('b_net', 'c_net', ess, 999),
      b('b_govt', 'c_govt', ess, 2000),
      b('b_insure', 'c_insure', ess, 786),
      b('b_house', 'c_house', ess, 6000),
      b('b_grocery', 'c_grocery', ess, 5000),
      b('b_food', 'c_food', ess, 4000),
      b('b_braces', 'c_braces', ess, 4500),
      b('b_family', 'c_family', ess, 2000),
      b('b_trans', 'c_trans', vari, 1500),
      b('b_fun', 'c_fun', vari, 2000),
      b('b_health', 'c_health', vari, 1000),
      b('b_shop', 'c_shop', vari, 1500),
      b('b_sub', 'c_sub', vari, 500),
      // Savings rows — one per goal that has a monthly set-aside.
      b('b_ef', 'a_ef', sav, 12000, type: BudgetType.goal),
      b('b_tuition', 'a_tuition', sav, 1000, type: BudgetType.goal),
      b('b_bday', 'a_bday', sav, 500, type: BudgetType.goal),
      b('b_bracesm', 'a_bracesm', sav, 500, type: BudgetType.goal),
      b('b_bracess', 'a_bracess', sav, 1000, type: BudgetType.goal),
      b('b_travel', 'a_travel', sav, 1000, type: BudgetType.goal),
      b('b_nice', 'a_nice', sav, 500, type: BudgetType.goal),
    ];
  }

  // ── Budgeted set-asides (one per goal fund, all still to fund) ──────────────
  static List<BudgetedExpense> _budgetedExpenses(String month) {
    BudgetedExpense e(String id, String name, double amount, String goalId,
            {SetAsideType type = SetAsideType.goal, String? note}) =>
        BudgetedExpense(
          id: id,
          name: name,
          budgetedType: type,
          month: month,
          allocatedAmount: amount,
          categoryId: 'c_savings',
          note: note,
          accountId: 'a_bpi',
          destinationAccountId: goalId,
          isRecurring: true,
          recurrenceType: RecurrenceType.monthly,
          seriesId: 'bes_$id',
        );

    return [
      e('be_ef', 'Emergency Fund', 12000, 'a_ef',
          type: SetAsideType.savings, note: '6 months of expenses'),
      e('be_tuition', 'Tuition Fund', 1000, 'a_tuition'),
      e('be_bday', 'Birthday Fund', 500, 'a_bday'),
      e('be_bracesm', 'Braces Maintenance Fund', 500, 'a_bracesm',
          type: SetAsideType.sinkingFund,
          note: 'For lost brackets, cleanings etc.'),
      e('be_bracess', 'Savings Braces Fund', 1000, 'a_bracess'),
      e('be_travel', 'Travel Fund', 1000, 'a_travel'),
      e('be_nice', 'Buy Something Nice Fund', 500, 'a_nice',
          type: SetAsideType.gift),
    ];
  }

  // ── Bills ───────────────────────────────────────────────────────────────────
  // 11 for the current month: 7 paid (₱12,429.27), 4 still due (₱7,885).
  static List<Bill> _bills(
      {required String month, required DateTime Function(int) paidOn}) {
    Bill bill(
      String id,
      String name,
      BillType type,
      double amount,
      int dueDay,
      String categoryId, {
      String? accountId,
      bool recurring = true,
      int? reminderDaysBefore,
      bool paid = false,
      String? transactionId,
    }) =>
        Bill(
          id: id,
          name: name,
          billType: type,
          amount: amount,
          dueDay: dueDay,
          month: month,
          categoryId: categoryId,
          accountId: accountId,
          isRecurring: recurring,
          recurrenceType: recurring ? RecurrenceType.monthly : null,
          seriesId: recurring ? 'bills_$id' : null,
          reminderDaysBefore: reminderDaysBefore,
          isPaid: paid,
          paidDate: paid ? paidOn(dueDay) : null,
          paidAmount: paid ? amount : null,
          transactionId: transactionId,
        );

    return [
      // Paid — government contributions.
      bill('bill_philhealth', 'Philhealth', BillType.govtContribution, 508, 8,
          'c_govt',
          accountId: 'a_gcash', paid: true, transactionId: 't_philhealth'),
      bill('bill_sss', 'SSS', BillType.govtContribution, 758, 8, 'c_govt',
          accountId: 'a_maya', paid: true, transactionId: 't_sss'),
      bill('bill_pagibig', 'Pag-Ibig Regular', BillType.govtContribution, 205,
          8, 'c_govt',
          accountId: 'a_maya', paid: true, transactionId: 't_pagibig'),
      bill('bill_mp2', 'Pag-Ibig MP2', BillType.govtContribution, 505, 8,
          'c_govt',
          accountId: 'a_maya', paid: true, transactionId: 't_mp2'),
      // Paid — card statements. Hand-keyed credit-card bills on the card's own
      // account id, which is what stops the statement generator from laying an
      // auto-statement on top of them.
      bill('bill_stmt_bpi', 'Credit Card CC (BPI) statement',
          BillType.creditCard, 2522.97, 5, 'c_ccpay',
          accountId: 'a_cc_bpi',
          recurring: false,
          paid: true,
          transactionId: 'g_pay_bpi_out'),
      bill('bill_stmt_maya', 'Credit Card (Maya) statement',
          BillType.creditCard, 5505.90, 10, 'c_ccpay',
          accountId: 'a_cc_maya',
          recurring: false,
          paid: true,
          transactionId: 'g_pay_maya_out'),
      bill('bill_stmt_shopee', 'ShopeePay statement', BillType.creditCard,
          2424.40, 15, 'c_ccpay',
          accountId: 'a_shopee',
          recurring: false,
          paid: true,
          transactionId: 'g_pay_shopee_out'),
      // Unpaid.
      bill('bill_elec', 'Electricity', BillType.utility, 1600, 16, 'c_bills',
          accountId: 'a_gcash'),
      bill('bill_insure', 'Insurance Premium', BillType.insurance, 786, 17,
          'c_insure',
          accountId: 'a_bpi'),
      bill('bill_brace', 'Brace Monthly', BillType.other, 4500, 24, 'c_braces',
          accountId: 'a_maya', reminderDaysBefore: 1),
      bill('bill_net', 'Internet', BillType.utility, 999, 25, 'c_net',
          accountId: 'a_mari'),
    ];
  }

  // ── Receivables ─────────────────────────────────────────────────────────────
  static List<Receivable> _receivables({
    required String month,
    required DateTime Function(int) dom,
    required DateTime Function(int) paidOn,
  }) =>
      [
        Receivable(
          id: 'rcv_salary',
          name: 'Alphaus Salary',
          receivableType: ReceivableType.salary,
          amount: 47976.59,
          expectedDate: dom(7),
          month: month,
          categoryId: 'c_salary',
          accountId: 'a_bpi',
          isRecurring: true,
          recurrenceType: RecurrenceType.monthly,
          seriesId: 'rcvs_salary',
          isReceived: true,
          receivedDate: paidOn(7),
          receivedAmount: 47976.59,
          transactionId: 't_salary',
        ),
        Receivable(
          id: 'rcv_papa',
          name: 'Papa Xiaomi',
          receivableType: ReceivableType.other,
          amount: 2000,
          expectedDate: dom(15),
          month: month,
          categoryId: 'c_reimb',
          accountId: 'a_bpi',
          isRecurring: true,
          recurrenceType: RecurrenceType.monthly,
          seriesId: 'rcvs_papa',
        ),
      ];

  // ── Installments (all on Credit Card CC (BPI), 0% add-on) ──────────────────
  // Six small plans bill this month; the two big-ticket ones were bought with a
  // deferral and start next month and the month after.
  static List<Installment> _installments({
    required String month,
    required DateTime Function(int) dom,
    required DateTime Function(int) prevDom,
    required DateTime Function(int) dAgo,
  }) {
    Installment plan(
      String id,
      String name,
      double total,
      int months,
      String startMonth,
      DateTime purchaseDate, {
      int deferral = 0,
      String? categoryId,
      String? note,
    }) =>
        Installment(
          id: id,
          name: name,
          accountId: 'a_cc_bpi',
          totalAmount: total,
          monthlyAmount: Installment.computeMonthlyAmount(
              principal: total, months: months),
          totalMonths: months,
          startMonth: startMonth,
          purchaseDate: purchaseDate,
          deferralMonths: deferral,
          categoryId: categoryId,
          note: note,
        );

    final next = nextMonth(month);
    final nextNext = nextMonth(next);
    return [
      plan('inst_fridge', 'Panasonic Refrigerator', 25992, 12, nextNext, dom(2),
          deferral: 2, categoryId: 'c_house', note: 'Inverter, 2-door'),
      plan('inst_xiaomi', "Papa's Xiaomi Redmi Note 15", 11999, 6, next,
          prevDom(28),
          deferral: 1, categoryId: 'c_tech', note: 'Papa pays ₱2,000/mo back'),
      plan('inst_bag', 'MENSPE Fashion Backpack', 627.48, 3, month, dAgo(6),
          categoryId: 'c_shop'),
      plan('inst_cam', 'Xiaomi Camera C301', 898.86, 3, month, dAgo(6),
          categoryId: 'c_tech'),
      plan('inst_cable', 'Solar DC Cable', 1118.28, 6, month, dAgo(5),
          categoryId: 'c_house'),
      plan('inst_inv', 'Pure Sine Wave Inverter', 1703.37, 12, month, dAgo(5),
          categoryId: 'c_house'),
      plan('inst_outlet', 'Extension Outlet', 139.38, 3, month, dAgo(4),
          categoryId: 'c_house'),
      plan('inst_fuse', 'ANL Fuse Holder', 248.76, 3, month, dAgo(4),
          categoryId: 'c_house'),
    ];
  }

  // ── Monthly summaries (the six closed months before this one) ───────────────
  // Frozen snapshots, oldest → newest, so the History table, the trend charts
  // and the live-month comparisons have a real past to draw. Net worth and
  // ending cash climb toward today's figures; category spend sums to a bit
  // under `expenses`, as a real close does once uncategorised adjustments are
  // left out.
  static List<MonthlySummary> _monthlySummaries(String month) {
    const income = [46500.0, 46500.0, 47976.59, 47976.59, 47976.59, 49976.59];
    const expenses = [31200.0, 28950.0, 33410.0, 30120.0, 35880.0, 29640.0];
    const endingCash = [21500.0, 24300.0, 27900.0, 30100.0, 28600.0, 31400.0];
    const netWorth = [38200.0, 41750.0, 44300.0, 48150.0, 50240.0, 52890.0];
    const saved = [3000.0, 3500.0, 4000.0, 4000.0, 5000.0, 12000.0];
    const totalBills = [9850.0, 9850.0, 10420.0, 10420.0, 12429.27, 12429.27];

    // Six month keys, oldest first.
    final keys = <String>[];
    var cursor = month;
    for (var i = 0; i < 6; i++) {
      cursor = previousMonth(cursor);
      keys.insert(0, cursor);
    }

    Map<String, double> spend(double total) => {
          'c_house': total * 0.22,
          'c_grocery': total * 0.16,
          'c_braces': total * 0.14,
          'c_food': total * 0.11,
          'c_bills': total * 0.08,
          'c_govt': total * 0.06,
          'c_trans': total * 0.05,
          'c_fun': total * 0.05,
          'c_health': total * 0.04,
          'c_family': total * 0.04,
        };

    return [
      for (var i = 0; i < keys.length; i++)
        MonthlySummary(
          month: keys[i],
          totalInflow: income[i],
          totalOutflow: expenses[i],
          totalBills: totalBills[i],
          totalBillsPaid: totalBills[i],
          billCount: 11,
          billsPaidCount: 11,
          totalReceivables: income[i],
          totalReceived: income[i],
          receivableCount: 2,
          netSavings: income[i] - expenses[i],
          endingCash: endingCash[i],
          accountSnapshots: const {},
          categorySpend: spend(expenses[i]),
          netWorth: netWorth[i],
          savingsContribution: saved[i],
        ),
    ];
  }
}
