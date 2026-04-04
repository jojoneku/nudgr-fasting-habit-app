# Plan 004f — Treasury Dashboard: Enrichment + Account Card Fix
**Status:** DRAFT — Awaiting Approval
**Phase:** Dashboard Enhancement (post-004b)
**Depends on:** Plan 004b completed, Plan 004c models available (Budget, BudgetedExpense)

---

## Goal

Two things:

1. **Bug Fix:** Account cards (horizontal scroll row) have a border radius mismatch — the non-uniform `Border` constructor in `BoxDecoration` does not respect `borderRadius` in Flutter, so the outline corners appear square while the background is rounded. Fix this visually.

2. **Dashboard Enrichment:** Add four new informational sections to the Treasury Dashboard that turn it from a simple balance viewer into a true financial health snapshot:
   - Monthly Budget Overview (allocated vs spent, per group)
   - Upcoming Bills (unpaid, sorted by due date)
   - Forecasted Net Balance metric (added to the existing banner)
   - Budget Goals Progress (per-group progress bars)

---

## Bug Fix: Account Card Border Radius

### Root Cause

`account_card_widget.dart` line 64–73:
```dart
decoration: BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(12),
  border: Border(              // ← non-uniform Border
    left: BorderSide(color: accentColor, width: 3),
    top: BorderSide(color: AppColors.accent.withOpacity(0.10), width: 1),
    right: BorderSide(color: AppColors.accent.withOpacity(0.10), width: 1),
    bottom: BorderSide(color: AppColors.accent.withOpacity(0.10), width: 1),
  ),
),
```

Flutter's `BoxDecoration` only applies `borderRadius` to the border when all sides are **uniform** (`Border.all()`). With mixed sides, the border corners are rendered sharp/square even though the background clip is rounded. This is a known Flutter constraint.

### Fix

Replace the non-uniform border approach with:
1. **Uniform thin outline** → `Border.all(color: AppColors.accent.withOpacity(0.10), width: 1)` — this WILL respect `borderRadius`
2. **Left accent bar** → rendered as a structural child widget inside the `Container`, not a border side

```dart
// BoxDecoration: uniform border only
decoration: BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: AppColors.accent.withOpacity(0.10), width: 1),
),

// Inner layout: Row with accent bar as first child
child: Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Container(
      width: 3,
      decoration: BoxDecoration(
        color: accentColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(11),    // inner radius = 12 - 1 (border width)
          bottomLeft: Radius.circular(11),
        ),
      ),
    ),
    Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(...),
      ),
    ),
  ],
),
```

**File changed:** `lib/views/treasury/dashboard/account_card_widget.dart`

---

## Dashboard Enrichment

### New Sections (inserted into `_DashboardScrollBody` after the liquid accounts row)

Layout order top-to-bottom after fix:
```
CashSummaryBanner          ← existing (+ Forecast metric added)
_LiquidAccountsRow         ← existing (bug fixed)
_UpcomingBillsCard         ← NEW
_BudgetOverviewCard        ← NEW
_GoalSection               ← existing
_LiabilitiesCard           ← existing
_HeldFundsCard             ← existing
```

---

### Section 1: Forecasted Net Balance (added to `CashSummaryBanner`)

Add a 4th metric to `_SummaryMetricsRow` in `cash_summary_banner.dart`:

| Label | Formula | Color |
|---|---|---|
| Forecast | `endingCash − totalBudgetRemaining` | accent if ≥ 0, danger if < 0 |

> "After paying all unpaid bills AND spending all remaining budgeted amounts, what's left in your pocket?"

**Presenter getter:**
```dart
double get forecastedNetBalance => endingCash - totalBudgetRemaining;
```

Note: If no budgets exist for the month, `forecastedNetBalance == endingCash`. The metric is hidden if `!hasBudget`.

The `_SummaryMetricsRow` becomes 2 rows of 2 metrics (to avoid cramping on small screens):
```
[ Ending Cash ]  |  [ Month In ]
─────────────────────────────────
[ Month Out ]    |  [ Forecast ]   ← only if hasBudget
```

---

### Section 2: Upcoming Bills (`_UpcomingBillsCard`)

**File:** `lib/views/treasury/dashboard/upcoming_bills_card.dart`

Shows unpaid bills for the current month, sorted by `dueDay` ascending.

```
UPCOMING BILLS
────────────────────────────────────
  📅 Meralco           due 5   ₱3,200  ← overdue if dueDay < today.day
  📅 SSS               due 10  ₱581
  📅 Netflix           due 15  ₱299
  ─ ─ ─ ─ ─
  [+ 2 more]   Total unpaid: ₱18,450
```

Rules:
- Show max 3 rows; if more, show "+ N more" tappable row (expands inline, no navigation)
- Overdue bills (dueDay < today's day): name shown in `AppColors.danger`, due date shows "Overdue"
- Total unpaid amount in footer row (bold, danger color if any are overdue)
- Hidden entirely if `!presenter.hasBills` (no bills for this month)

**Presenter getter:**
```dart
List<Bill> get upcomingBills => _bills
    .where((b) => b.month == _currentMonth && !b.isPaid)
    .toList()
  ..sort((a, b) => a.dueDay.compareTo(b.dueDay));

bool get hasBills => upcomingBills.isNotEmpty;
```

---

### Section 3: Monthly Budget Overview (`_BudgetOverviewCard`)

**File:** `lib/views/treasury/dashboard/budget_overview_card.dart`

Shows budget health across the three `BudgetGroup` buckets.

```
BUDGET THIS MONTH
────────────────────────────────────
  Total  ████████░░  ₱24,800 / ₱38,000  65%

  Non-Negotiables    ████████░░  ₱12,000 / ₱15,000
  Living Expenses    █████░░░░░  ₱8,300 / ₱16,000
  Variable           ████░░░░░░  ₱4,500 / ₱7,000
```

Each row:
- Group label (left)
- Slim `LinearProgressIndicator` (center, color-coded by % used)
- `₱spent / ₱allocated` (right, JetBrains Mono)

Progress bar colors:
| % Used | Color |
|---|---|
| < 75% | `AppColors.success` |
| 75–99% | `AppColors.warning` (amber `#FFB300`) |
| ≥ 100% | `AppColors.danger` |

Hidden entirely if `!presenter.hasBudget`.

**Presenter getters:**
```dart
bool get hasBudget;
double get totalBudgetAllocated;     // sum of all Budget.allocatedAmount for currentMonth
double get totalBudgetSpent;         // sum of all BudgetedExpense.spentAmount for currentMonth
double get totalBudgetRemaining;     // totalBudgetAllocated - totalBudgetSpent

Map<BudgetGroup, double> get budgetAllocatedByGroup;
Map<BudgetGroup, double> get budgetSpentByGroup;
```

---

## Affected Files

| File | Change | Layer |
|---|---|---|
| `lib/views/treasury/dashboard/account_card_widget.dart` | Fix border + restructure inner layout | View |
| `lib/views/treasury/dashboard/cash_summary_banner.dart` | Add Forecast metric, restructure to 2×2 grid | View |
| `lib/views/treasury/dashboard/upcoming_bills_card.dart` | **Create** — new widget | View |
| `lib/views/treasury/dashboard/budget_overview_card.dart` | **Create** — new widget | View |
| `lib/views/treasury/dashboard/treasury_dashboard_view.dart` | Insert new cards into `_DashboardScrollBody` | View |
| `lib/presenters/treasury_dashboard_presenter.dart` | Load budgets + budgeted expenses; add 7 new getters | Presenter |

---

## New Presenter Interface (additions only)

```dart
// Add to TreasuryDashboardPresenter

// Data (loaded in load())
List<Budget> _budgets = [];
List<BudgetedExpense> _budgetedExpenses = [];

// Budget summary
bool get hasBudget;
double get totalBudgetAllocated;
double get totalBudgetSpent;
double get totalBudgetRemaining;
double get forecastedNetBalance;
Map<BudgetGroup, double> get budgetAllocatedByGroup;
Map<BudgetGroup, double> get budgetSpentByGroup;

// Bills
List<Bill> get upcomingBills;
bool get hasBills;
```

StorageService already exposes `loadBudgets()` and `loadBudgetedExpenses()` — no service changes needed.

---

## UX Rules

- All new cards use `_SectionHeader` widget (consistent look with Goals & Savings)
- No navigation triggered from new cards — all info is inline or expandable
- Budget progress bars animate on first render (150ms, `AnimatedContainer` or `TweenAnimationBuilder`)
- Overdue bills pulse red using `AnimatedOpacity` (0.5 → 1.0, 800ms loop) — subtle urgency signal
- If both Upcoming Bills and Budget are empty, dashboard retains existing compact appearance

---

## Acceptance Criteria

- [ ] Account card borders follow the rounded corners exactly — no square-cornered outline
- [ ] Left accent bar color matches the account's `colorHex`
- [ ] Forecast metric appears in banner only when budget data exists for the month
- [ ] Upcoming Bills shows max 3 rows; "+ N more" expands the rest inline
- [ ] Overdue bills show name in danger red with "Overdue" label
- [ ] Budget Overview shows all 3 groups with correct progress values
- [ ] Progress bar color shifts to amber at 75% and red at 100%
- [ ] All new sections hidden gracefully when no data exists (no empty-state blocks)
- [ ] No logic in any `build()` method — all calculations in Presenter getters
- [ ] All touch targets ≥ 44×44px

---

*Present this plan for approval before writing any code.*
