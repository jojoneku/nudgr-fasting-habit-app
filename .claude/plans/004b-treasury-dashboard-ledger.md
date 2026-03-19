# Plan 004b — Treasury Module: Dashboard + Ledger
**Status:** DRAFT v2 — Awaiting Approval (updated: sub-accounts, no seeding)
**Phase:** 2 of 3
**Depends on:** Plan 004a completed

---

## Goal

Build the two highest-value screens of the Treasury module:

1. **Dashboard** — at-a-glance financial health snapshot
2. **Ledger** — full transaction log with add/edit/delete and per-account balance

These are the screens the user opens daily. Accuracy and speed of reading matter most here.

---

## Dashboard Screen Spec

### What's shown (top to bottom):

| Widget | Data |
|---|---|
| **Total Liquid Cash Card** | Sum of all *liquid* account balances (bank + ewallet + cash only) |
| **Ending Cash Banner** | `liquidCash + pendingReceivables − unpaidBills` |
| **Account Cards** (horizontal scroll) | Liquid accounts only — name, icon, balance. Tap to expand sub-accounts |
| **Sub-account Drawer** (on tap) | Lists savings/goals/time deposits/investments under that parent, each with progress bar if goal |
| **Goal & Fund Cards** | All `goal` and `savings` sub-accounts with target % (e.g. Braces Fund ₱24,500 / ₱50,000) |
| **Liabilities Card** | Sum of all credit cards + credit lines + BNPL outstanding balances (shown in red, collapsible list) |
| **Quick Actions** | + Add Transaction, + Add Bill, + Add Receivable |

**Note:** "Total Cash In Accounts" from your sheet = liquid cash only (main accounts). Goal/savings sub-accounts are shown separately — they're not counted as spendable.

### Dashboard Calculations (all in Presenter, never in build()):

```dart
// All getters on TreasuryDashboardPresenter
double get totalLiquidCash;      // sum of liquid accounts (bank + ewallet + cash only)
double get totalLiabilities;     // sum of liability account balances (creditCard + creditLine + bnpl)
double get endingCash;           // totalLiquidCash + pendingReceivables - unpaidBills
double get monthTotalInflow;     // sum of inflow transactions this month
double get monthTotalOutflow;    // sum of outflow transactions this month
double get monthUnpaidBills;     // sum of unpaid bill amounts this month
double get pendingReceivables;   // sum of unreceived receivables this month
List<FinancialAccount> get liquidAccounts;       // bank + ewallet + cash (top-level only)
List<FinancialAccount> get liabilityAccounts;    // creditCard + creditLine + bnpl
List<FinancialAccount> subAccountsOf(String parentId); // savings/goal/timeDeposit pockets
List<FinancialAccount> get goalAccounts;         // all sub-accounts of category == goal
List<FinancialAccount> get savingsAccounts;      // all sub-accounts of category == savings
```

---

## Ledger Screen Spec

### Layout:

- **Account filter chips** at top (All | BPI | GCash | Cash | …) — includes sub-accounts as separate filter options
- **Month selector** (← March 2026 →) — swipe or tap arrows
- **Transaction list** grouped by date, descending
- **Running balance** shown per account when filtered to one account
- **FAB** → Add Transaction bottom sheet

### Running Balance

The Balance column is a **global running total** across all liquid accounts combined (matching your Excel sheet). It is NOT per-account. This means:
- Every transaction — regardless of which account — moves the global balance up or down
- The latest balance equals `totalLiquidCash` on the Dashboard
- When filtered to one specific account, balance column is hidden (it would be misleading)
- Credit card outflows (charges) decrease the global balance at time of spend, not at payment time

### Per Transaction Row:

```
[Category Icon]  [Description]          [± Amount]
                 [Account · Date]        [Global running bal]
```

### Add/Edit Transaction Bottom Sheet Fields:

| Field | Type | Notes |
|---|---|---|
| Amount | Number input | Always positive |
| Type | Toggle (Inflow / Outflow / Transfer) | |
| Account | Dropdown | Required |
| Category | Picker grid | Filtered by type |
| Description | Text | Max 60 chars |
| Date | Date picker | Defaults to today |
| Note | Text (optional) | |
| Link to Bill | Toggle + picker | Only if Outflow |
| Link to Receivable | Toggle + picker | Only if Inflow |
| Is Adjustment | Toggle | Special reconciliation entry — no category required, just corrects global balance |

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/presenters/treasury_dashboard_presenter.dart` | Create | Presenter |
| `lib/presenters/ledger_presenter.dart` | Create | Presenter |
| `lib/views/treasury/treasury_module_view.dart` | Create | View |
| `lib/views/treasury/dashboard/treasury_dashboard_view.dart` | Create | View |
| `lib/views/treasury/dashboard/account_card_widget.dart` | Create | View |
| `lib/views/treasury/dashboard/cash_summary_banner.dart` | Create | View |
| `lib/views/treasury/dashboard/goal_progress_card.dart` | Create | View |
| `lib/views/treasury/ledger/ledger_view.dart` | Create | View |
| `lib/views/treasury/ledger/transaction_list_tile.dart` | Create | View |
| `lib/views/treasury/ledger/add_transaction_sheet.dart` | Create | View |
| `lib/views/treasury/shared/account_setup_view.dart` | Create | View |

---

## Interface Definitions

### TreasuryDashboardPresenter

```dart
class TreasuryDashboardPresenter extends ChangeNotifier {
  TreasuryDashboardPresenter(StorageService storage);

  // State
  bool get isLoading;
  String get currentMonth; // 'YYYY-MM'

  // Dashboard getters
  double get netWorth;
  double get endingCash;
  double get savingsBalance;
  double get efBalance;
  double get savingsGoalPercent;  // 0.0 – 1.0+
  double get efGoalPercent;       // 0.0 – 1.0+
  double get monthTotalInflow;
  double get monthTotalOutflow;
  double get monthUnpaidBills;
  List<FinancialAccount> get activeAccounts;
  bool get hasAccounts; // false → show onboarding prompt

  // Actions
  Future<void> load();
  Future<void> setSavingsGoal(double amount);
  Future<void> setEfGoal(double amount);
}
```

### LedgerPresenter

```dart
class LedgerPresenter extends ChangeNotifier {
  LedgerPresenter(StorageService storage);

  // Filters
  String get selectedMonth;
  String? get selectedAccountId; // null = all accounts
  void setMonth(String month);   // 'YYYY-MM'
  void setAccount(String? id);

  // Data
  List<FinancialAccount> get accounts;
  List<FinanceCategory> get categories;
  Map<DateTime, List<TransactionRecord>> get groupedTransactions;
  double get filteredAccountBalance;    // running bal (single account only)
  double get filteredMonthInflow;
  double get filteredMonthOutflow;

  // CRUD
  Future<void> addTransaction(TransactionRecord);
  Future<void> updateTransaction(TransactionRecord);
  Future<void> deleteTransaction(String id);

  // After add/update/delete: recalculate account.balance and call notifyListeners()
}
```

---

## RPG Impact

- **+10 XP** the first time the user logs a transaction each day (daily habit reward)
- **+25 XP** when the user logs their first transaction ever (onboarding completion)
- XP is awarded via `StatsPresenter.addXp()` — called from `LedgerPresenter` after a successful add
- Stat connection: financial logging boosts **INT** — not yet automated, manual in this phase

---

## Navigation Entry Point

Treasury module is entered from the Hub card (Plan 001). The `TreasuryModuleView` hosts a `PageView` or `TabBar` with 4 sections:

```
[ Dashboard ] [ Ledger ] [ Bills & Budget ] [ History ]
```

Dashboard is the default tab (index 0).

---

## UX Rules

- Account balance chips use the account's `colorHex` as the card accent
- Amounts: outflows shown in **red**, inflows in **green/cyan**, transfers in **amber**
- "Ending Cash" tooltip explains the formula on long-press
- Empty state (no accounts): show "Add your first account" CTA, not a blank screen
- Month selector: swipe gesture + header tap to jump to month picker

---

## Account Setup Flow (First Launch)

When `hasAccounts == false`, show an empty-state card with a "Add your first account" CTA (bottom sheet, not a separate route).

**Create Account sheet fields:**
- Name (text)
- Category: Bank / E-Wallet / Cash (picker — sub-account types are not selectable here)
- Opening Balance (number)
- Color + Icon (picker)

**Add Sub-Account** — available from a main account's detail or long-press. Same sheet but:
- Parent account is pre-filled and locked
- Category: Savings / Goal / Time Deposit (picker)
- If Goal: add Goal Target amount field
- If Time Deposit: add Maturity Date field

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Account balance desync on delete | On `deleteTransaction`, reverse the balance delta on the linked account before removing |
| Transfer shown twice in "All Accounts" ledger | In "All Accounts" view, show only the **outflow leg** of each transfer pair (identified by `transferGroupId`). When filtered to a specific account, show both legs that belong to that account (could be inflow *or* outflow). This applies to main→sub transfers too (e.g. Maya → Braces Fund). |
| Sub-account balance included in liquid cash total | Only `isLiquid` accounts count toward `totalLiquidCash`; sub-accounts are excluded |
| Deleting a main account with sub-accounts | Block deletion if sub-accounts exist — prompt user to delete or reassign sub-accounts first |
| Large transaction lists slow scroll | Use `ListView.builder` — never `Column` |
| Concurrent writes during month change | `LedgerPresenter.setMonth()` cancels in-flight load with a cancellation token pattern |
| Negative balance | Allow it — show balance in red with a warning icon |

---

## Acceptance Criteria

- [ ] Dashboard loads and displays all 5 summary values with no layout overflow
- [ ] Account cards scroll horizontally with correct balances
- [ ] Ledger groups transactions by date, most recent first
- [ ] Adding a transaction updates both the ledger list and the linked account balance immediately
- [ ] Deleting a transaction reverses the account balance delta
- [ ] Transfer creates exactly 2 TransactionRecords (one per account)
- [ ] Empty-account state shows onboarding prompt, not blank screen
- [ ] All touch targets ≥ 44×44px
- [ ] No logic in any `build()` method — all calculations in Presenter getters

---

*Present this plan for approval before writing any code. Proceed to Plan 004c after approval.*
