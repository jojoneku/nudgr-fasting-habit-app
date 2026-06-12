/// One-time historical backfill for the Treasury module.
///
/// These figures are imported from the legacy "Personal_Financials_2026v2"
/// Google Sheet (the laptop spreadsheet the web companion replaces). They cover
/// the closed months Jan–May 2026 so the dashboard's Net-Worth and
/// Income-vs-Expenses trends — and the History page — show real history instead
/// of starting empty.
///
/// Source of truth & aggregation (verified against the sheet's summary tab):
///   • income   = "Total Income"   (sum of Income-category inflows; excludes transfers)
///   • expenses = "Total Expenses" (sum of expense-category outflows; excludes
///                transfers/savings; a few ₱k/mo of `Adjustment`-type outflow in
///                Apr/May is not in the per-category matrix, so per-category spend
///                may sum slightly below `expenses` — `expenses` is authoritative)
///   • net      = income − expenses (matches the sheet's "Net Cash Flow")
///   • category spend = the "Spending by Category" matrix, keyed by category NAME
///     (mapped to the user's category ids at import time; zero rows omitted)
///
/// Month-end NET WORTH is NOT stored in the sheet, so it is reconstructed at
/// import time by walking the live current net worth backwards through these
/// monthly net-cash-flows (same basis as the sheet's "Cumulative Net" row). This
/// avoids summing the sheet's per-account balances, where credit cards are
/// stored as *available limit* and would corrupt a naïve net-worth sum.
class HistoricalMonthBackfill {
  final String month; // 'YYYY-MM'
  final double income;
  final double expenses;
  final double net; // income - expenses
  final Map<String, double> categorySpendByName;

  const HistoricalMonthBackfill({
    required this.month,
    required this.income,
    required this.expenses,
    required this.net,
    required this.categorySpendByName,
  });
}

/// Jan–May 2026, oldest → newest. June 2026 is the live (in-progress) month and
/// is intentionally excluded — the app computes it from real transactions.
const List<HistoricalMonthBackfill> kTreasuryHistoryBackfill2026 = [
  HistoricalMonthBackfill(
    month: '2026-01',
    income: 39563,
    expenses: 37939,
    net: 1624,
    categorySpendByName: {
      'Bills & Utilities': 14741,
      'Household Expenses': 14360,
      'Food & Drinks': 3818,
      'Transportation': 1340,
      'Guilt-Free/Fun': 905,
      'Health & Wellness': 899,
      'Internet': 249,
      'Shopping & Personal': 1317,
      'Education/Professional': 250,
      'Transfer Fees': 61,
    },
  ),
  HistoricalMonthBackfill(
    month: '2026-02',
    income: 54097,
    expenses: 43580,
    net: 10517,
    categorySpendByName: {
      'Bills & Utilities': 16850,
      'Household Expenses': 15062,
      'Food & Drinks': 2481,
      'Transportation': 2215,
      'Guilt-Free/Fun': 3972,
      'Health & Wellness': 700,
      'Internet': 249,
      'Shopping & Personal': 813,
      'Debt Repayment': 1238,
    },
  ),
  HistoricalMonthBackfill(
    month: '2026-03',
    income: 51001,
    expenses: 47097,
    net: 3904,
    categorySpendByName: {
      'Bills & Utilities': 7032,
      'Household Expenses': 13393,
      'Food & Drinks': 3203,
      'Transportation': 2390,
      'Guilt-Free/Fun': 1663,
      'Health & Wellness': 859,
      'Business Expense': 15644,
      'Shopping & Personal': 551,
      'For Reimbursement': 2344,
      'Transfer Fees': 18,
    },
  ),
  HistoricalMonthBackfill(
    month: '2026-04',
    income: 65650,
    expenses: 57653,
    net: 7997,
    categorySpendByName: {
      'Bills & Utilities': 20307,
      'Household Expenses': 16087,
      'Food & Drinks': 2543,
      'Transportation': 3682,
      'Guilt-Free/Fun': 3031,
      'Health & Wellness': 1408,
      'Business Expense': 2971,
      'Education/Professional': 35,
      'For Reimbursement': 4139,
      'Transfer Fees': 36,
    },
  ),
  HistoricalMonthBackfill(
    month: '2026-05',
    income: 75471,
    expenses: 43263,
    net: 32208,
    categorySpendByName: {
      'Bills & Utilities': 6522,
      'Household Expenses': 15627,
      'Food & Drinks': 3222,
      'Transportation': 1807,
      'Guilt-Free/Fun': 2281,
      'Health & Wellness': 380,
      'Internet': 498,
      'Business Expense': 2799,
      'For Reimbursement': 5904,
      'Transfer Fees': 36,
    },
  ),
];
