import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';

/// Predicates that decide what counts as real spending and real income.
///
/// Three kinds of money movement are NOT income or expense and must be excluded
/// from every headline/summary figure:
///   1. Internal transfers (transferGroupId != null) — moving your own money.
///   2. Reimbursables / loans — money you front or lend and will get back. The
///      outflow isn't spending (it's an asset/receivable), and its repayment
///      inflow isn't income (you're getting your own money back). Only a
///      written-off loan would ever become a real expense.
///   3. Transactions in a category the user flagged [excludeFromTotals] — e.g.
///      a "Reimbursement" income category for paybacks logged directly (not via
///      the linked reimbursable-expense flow). Pass the set from
///      [excludedCashFlowCategoryIds].
///
/// Salary/business receivable repayments are real income and are intentionally
/// NOT excluded — they don't originate from a reimbursable outflow, so their
/// `receivableId` won't appear in [reimbursementReceivableIds].

/// Ids of categories the user flagged to exclude from cash-flow totals. Pass
/// the result to [isSpendingOutflow] / [isIncomeInflow].
Set<String> excludedCashFlowCategoryIds(Iterable<FinanceCategory> categories) {
  return {
    for (final c in categories)
      if (c.excludeFromTotals) c.id,
  };
}

/// Receivable ids spawned by reimbursable/loan outflows. A repayment inflow
/// carries one of these as its `receivableId` (the spawned receivable reuses the
/// outflow's `reimbursementReceivableId` as its id, and the settling inflow
/// references that id). Build from the FULL transaction list so a repayment is
/// matched even when its originating outflow is in another month/account.
Set<String> reimbursementReceivableIds(Iterable<TransactionRecord> all) {
  return {
    for (final t in all)
      if (t.reimbursable && t.reimbursementReceivableId != null)
        t.reimbursementReceivableId!,
  };
}

/// True for an outflow that is real spending — excludes internal transfer legs,
/// reimbursable/loan outflows (money you'll get back isn't an expense), and any
/// outflow in an [excludeFromTotals] category. [excludedCategoryIds] comes from
/// [excludedCashFlowCategoryIds].
bool isSpendingOutflow(TransactionRecord t,
        [Set<String> excludedCategoryIds = const {}]) =>
    t.type == TransactionType.outflow &&
    t.transferGroupId == null &&
    !t.reimbursable &&
    !excludedCategoryIds.contains(t.categoryId);

/// True for an inflow that is real income — excludes internal transfer legs,
/// the repayment of a reimbursable/loan (getting your own money back isn't
/// income), and any inflow in an [excludeFromTotals] category.
/// [reimbursementIds] comes from [reimbursementReceivableIds];
/// [excludedCategoryIds] from [excludedCashFlowCategoryIds].
bool isIncomeInflow(TransactionRecord t, Set<String> reimbursementIds,
        [Set<String> excludedCategoryIds = const {}]) =>
    t.type == TransactionType.inflow &&
    t.transferGroupId == null &&
    !(t.receivableId != null && reimbursementIds.contains(t.receivableId)) &&
    !excludedCategoryIds.contains(t.categoryId);
