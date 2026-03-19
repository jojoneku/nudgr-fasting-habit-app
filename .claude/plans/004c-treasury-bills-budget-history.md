# Plan 004c — Treasury Module: Bills, Budget & History
**Status:** DRAFT v2 — Awaiting Approval (updated from sheet screenshots)
**Phase:** 3 of 3
**Depends on:** Plan 004b completed

---

## Goal

Complete the Treasury module with three remaining screens:

1. **Bills & Receivables** — monthly bill tracker, expected income, budgeted expense buckets
2. **Budget** — category spending limits for the month with remaining amounts
3. **Historical Summary** — frozen monthly snapshots, comparable over time

---

## Bills & Receivables Screen Spec

### Layout — Three sub-sections (vertical tabs or accordion):

#### Section A: Bills
- List of bills for current month
- Each row: name, bill type badge, amount, due date, payment account note, **paid / unpaid** toggle
- Paid row shows: paid amount (may differ from billed) + paid date
- **"Next Month" chip** on each row — tap to pre-set the amount for next month
- Tapping "Mark Paid" → bottom sheet to confirm amount + account → creates linked `TransactionRecord`
- FAB → Add Bill sheet (fields: Name, Bill Type, Amount, Due Day, Account, Payment Note, Recurring toggle)

#### Section B: Receivables
- Expected income for current month
- Each row: source name, receivable type badge, expected amount, expected date, **received / outstanding** toggle
- **"Next Month" chip** on each row — tap to pre-set amount for next month
- Tapping "Mark Received" → confirm received amount → creates linked `TransactionRecord`
- FAB → Add Receivable sheet (fields: Source, Type, Amount, Expected Date, Recurring toggle)

#### Section C: Budgeted Expenses
- Pre-planned spending commitments (e.g. Family Support, Braces Sinking Fund, Emergency Fund top-up)
- Each row: name, type, allocated amount, actual spent, **paid / unpaid** toggle, notes (e.g. "Maya Savings")
- **"Next Month" chip** on each row — tap to pre-set amount for next month
- Tapping "Mark Paid" → confirm actual amount → creates linked `TransactionRecord`
- FAB → Add Budgeted Expense sheet

### Key Stats Bar (top of screen):
```
Bills: ₱1,278 outstanding  |  Paid: ₱4,316  |  Next Month: ₱5,695
```

---

## Budget Screen Spec

### Layout:

- **Month selector** (same as Ledger)
- **3 grouped sections** matching the Excel sheet:

```
┌─ NON-NEGOTIABLES ─────────────── Target: ₱71,500  Actual: ₱68,854 ─┐
│ Income       Monthly  ₱51,000 / ₱50,000  ████████████  102% [green] │
│ Bills & Util Fixed    ₱5,754 / ₱8,500    ███████░░░░░   68%         │
│ Savings      Goal     ₱12,100 / ₱13,000  ███████████░   93%         │
└─────────────────────────────────────────────────────────────────────┘

┌─ LIVING EXPENSE ──────────────── Target: ₱9,501   Actual: ₱9,650 ──┐
│ Food & Drinks  Variable  ₱2,513 / ₱2,500  █████████████ 101% [red]  │
│ Groceries      Variable  ₱2,175 / ₱2,000  ████████████  109% [red]  │
│ ...                                                                   │
└─────────────────────────────────────────────────────────────────────┘

┌─ VARIABLE/OPTIONAL ───────────── Target: ₱12,000  Actual: ₱10,000 ─┐
│ Family & Giving  Fixed    ₱10,000 / ₱10,000  100%                   │
│ Travel Fund      Variable ₱0 / ₱1,000         0%                    │
│ ...                                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

- Tap a category row → expand to show transactions in that category this month
- FAB → Add/Edit budget for a category (with group + type selector)

### Budget Rules:
- Budget is per-month per-category
- Each budget row has a `BudgetGroup` (which section it belongs to) and `BudgetType` (affects row styling)
- Income rows are displayed with inverted logic: over = green (earned more than target), under = yellow
- Over-budget expense rows show amount in red with warning icon
- Unspent budget does NOT roll over — rollover is a future feature

---

## Historical Summary Screen Spec

### Layout:

- **Month list** — most recent first, tap to expand
- Each month card shows:
  ```
  ┌──────────────────────────────────────────────┐
  │  March 2026                                  │
  │  Net Savings: +₱8,500  |  Ending Cash: ₱52k │
  │  Bills: 8/10 paid  |  Receivables: 3/4 received │
  │  Top Spend: Food ₱4,200                      │
  └──────────────────────────────────────────────┘
  ```
- Tap → `MonthlySummaryDetailView` with full breakdown
- Month is "closed" automatically on the 1st of next month
  (a `MonthlySummary` snapshot is computed and frozen)

### MonthlySummaryDetailView sections:
- Income vs. Expense bar chart (simple horizontal bars)
- Account balances at month end
- Category spend breakdown
- Bills paid / unpaid list
- Receivables received / pending list

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/presenters/bills_receivables_presenter.dart` | Create | Presenter |
| `lib/presenters/budget_presenter.dart` | Create | Presenter |
| `lib/presenters/treasury_history_presenter.dart` | Create | Presenter |
| `lib/views/treasury/bills/bills_receivables_view.dart` | Create | View |
| `lib/views/treasury/bills/bill_list_tile.dart` | Create | View |
| `lib/views/treasury/bills/receivable_list_tile.dart` | Create | View |
| `lib/views/treasury/bills/budgeted_expense_tile.dart` | Create | View |
| `lib/views/treasury/bills/add_bill_sheet.dart` | Create | View |
| `lib/views/treasury/bills/add_receivable_sheet.dart` | Create | View |
| `lib/views/treasury/budget/budget_view.dart` | Create | View |
| `lib/views/treasury/budget/category_budget_tile.dart` | Create | View |
| `lib/views/treasury/budget/add_budget_sheet.dart` | Create | View |
| `lib/views/treasury/history/treasury_history_view.dart` | Create | View |
| `lib/views/treasury/history/monthly_summary_card.dart` | Create | View |
| `lib/views/treasury/history/monthly_summary_detail_view.dart` | Create | View |

---

## Interface Definitions

### BillsReceivablesPresenter

```dart
class BillsReceivablesPresenter extends ChangeNotifier {
  BillsReceivablesPresenter(StorageService storage, LedgerPresenter ledger);

  String get selectedMonth;
  void setMonth(String month);

  // Bills
  List<Bill> get bills;
  double get totalBillsAmount;
  double get totalBillsPaid;
  double get totalBillsPending;
  Future<void> addBill(Bill);
  Future<void> updateBill(Bill);
  Future<void> deleteBill(String id);
  Future<void> markBillPaid(String billId, {DateTime? paidDate});
  // ^ creates a TransactionRecord via LedgerPresenter

  // Receivables
  List<Receivable> get receivables;
  double get totalReceivablesAmount;
  double get totalReceived;
  Future<void> addReceivable(Receivable);
  Future<void> updateReceivable(Receivable);
  Future<void> deleteReceivable(String id);
  Future<void> markReceivableReceived(String receivableId, {DateTime? receivedDate});
  // ^ creates a TransactionRecord via LedgerPresenter

  // Budgeted Expenses
  List<BudgetedExpense> get budgetedExpenses;
  Future<void> addBudgetedExpense(BudgetedExpense);
  Future<void> updateBudgetedExpense(BudgetedExpense);
  Future<void> deleteBudgetedExpense(String id);
  double spentForBudgetedExpense(String id); // computed from transactions
}
```

### BudgetPresenter

```dart
class BudgetPresenter extends ChangeNotifier {
  BudgetPresenter(StorageService storage, LedgerPresenter ledger);

  String get selectedMonth;
  void setMonth(String month);

  double get totalAllocated;
  double get totalSpent;
  double get totalRemaining; // may be negative
  List<FinanceCategory> get expenseCategories;
  Budget? budgetFor(String categoryId);
  double spentFor(String categoryId); // sum of transactions this month
  double remainingFor(String categoryId);
  bool isOverBudget(String categoryId);

  Future<void> setBudget(String categoryId, double amount);
  Future<void> removeBudget(String categoryId);
}
```

### TreasuryHistoryPresenter

```dart
class TreasuryHistoryPresenter extends ChangeNotifier {
  TreasuryHistoryPresenter(StorageService storage);

  List<MonthlySummary> get summaries; // sorted most recent first
  MonthlySummary? get currentMonthSummary; // live, not yet frozen
  Future<void> load();
  Future<void> closePreviousMonth(); // called automatically on first load of new month
  // ^ computes MonthlySummary from raw data and saves it frozen
}
```

---

## Month-Close Logic

When `TreasuryHistoryPresenter` loads and detects the current month differs from the last closed month:

1. Compute `MonthlySummary` from all transactions, bills, receivables in the previous month
2. Save the frozen `MonthlySummary` to storage
3. Auto-generate recurring bills for the new month (copy `isRecurring == true` bills)
4. Auto-generate recurring receivables for the new month

This runs once per month, idempotently (check if summary already exists before creating).

---

## RPG Impact

| Action | Reward | Stat |
|---|---|---|
| All bills paid for the month | +50 XP | INT +1 (once per level) |
| Savings goal reached | +75 XP | INT +1 (once per level) |
| EF goal reached | +100 XP | INT +1 (once per level) |
| Budget not exceeded for the month | +30 XP | — |
| Consecutive months with no over-budget | Streak tracked, +10 XP/month bonus | — |

XP awarded via `StatsPresenter.addXp()` called from each Presenter on the achievement condition.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Month-close fires multiple times | Guard with "summary already exists for month X" check |
| Recurring bill amounts change mid-year | Recurring copy uses last known amount; user edits the new month's copy |
| Bill "Mark Paid" with no account set | Default to first active account; prompt user to confirm |
| Budget screen with no budgets set | Show friendly "No budgets yet — tap + to set spending limits" empty state |
| History chart with only 1 month | Hide comparison deltas; show single bar chart with no trend line |
| Large history (2+ years) slow to load | Paginate — load 6 months at a time, infinite scroll upward |

---

## Acceptance Criteria

- [ ] Bills list shows correct paid/unpaid totals
- [ ] Marking a bill paid creates a matching TransactionRecord and updates account balance
- [ ] Marking a receivable received creates a matching TransactionRecord
- [ ] Budget screen shows correct spent/remaining per category
- [ ] Over-budget categories display amount in red
- [ ] Month-close creates a frozen MonthlySummary on first load of new month
- [ ] Recurring bills auto-generate in new month
- [ ] Historical summary list shows at least current month (live) and previous month (frozen)
- [ ] XP awarded correctly on bill-paid-all and savings-goal-reached events
- [ ] All touch targets ≥ 44×44px
- [ ] No logic in any `build()` method

---

*This completes the Treasury module plan trilogy (004a → 004b → 004c).*
*Full implementation order: 004a → 004b → 004c → integrate into Hub (Plan 001).*
