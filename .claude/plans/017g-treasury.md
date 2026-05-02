# Plan 017g — Treasury Module Redesign

> Depends on **017** (tokens + theme) and **017W** (widget library) being merged.

## Goal

Treasury is the largest module — dashboard, ledger, bills, budget, history. Apply the design system uniformly so it reads as one coherent finance app instead of five mini-screens.

---

## Files Touched

### Module Root
| File | Action |
|---|---|
| `lib/views/treasury/treasury_module_view.dart` | Tab-host shell using theme `NavigationBar` / `TabBar` defaults |
| `lib/views/treasury/shared/account_setup_view.dart` | Onboarding rewrite — `AppPageScaffold` + `AppCard` form blocks |

### Dashboard
| File | Action |
|---|---|
| `dashboard/treasury_dashboard_view.dart` | Page rewrite with `AppPageScaffold` + `AppSection`s |
| `dashboard/cash_summary_banner.dart` | Refactor as `AppCard` (filled), DM Mono totals |
| `dashboard/account_card_widget.dart` | Compose `AppCard`; balance in `AppNumberDisplay` |
| `dashboard/metric_cards_grid.dart` | 2-col grid of `AppCard`s, each with `AppNumberDisplay` |
| `dashboard/budget_overview_card.dart` | `AppCard` + nested `AppLinearProgress` per category |
| `dashboard/category_pie_chart_card.dart` | `AppCard` wrapping the chart; theme-aware colors |
| `dashboard/spending_analytics_card.dart` | `AppCard`; bar/line chart colors from theme |
| `dashboard/upcoming_bills_card.dart` | `AppCard` containing list of `AppListTile`s |
| `dashboard/goal_progress_card.dart` | `AppCard` + `AppLinearProgress` |
| `dashboard/full_category_breakdown_sheet.dart` | Wrap with `AppBottomSheet` |
| `dashboard/full_spending_history_sheet.dart` | Wrap with `AppBottomSheet` |

### Ledger
| File | Action |
|---|---|
| `ledger/ledger_view.dart` | Grouped `AppListTile` list |
| `ledger/transaction_list_tile.dart` | Replace internals with `AppListTile` composition |
| `ledger/spending_calendar.dart` | Theme-aware heatmap colors; `AppCard` wrapper |
| `ledger/add_transaction_sheet.dart` | Wrap with `AppBottomSheet` |
| `ledger/manage_categories_sheet.dart` | Wrap with `AppBottomSheet`; rows as `AppSelectableTile` |

### Bills
| File | Action |
|---|---|
| `bills/bills_receivables_view.dart` | Sectioned `AppListTile` lists |
| `bills/bill_list_tile.dart` / `installment_list_tile.dart` / `receivable_list_tile.dart` / `budgeted_expense_tile.dart` | Compose `AppListTile`; trailing amount in DM Mono |
| `bills/add_bill_sheet.dart` / `add_installment_sheet.dart` / `add_receivable_sheet.dart` | Wrap with `AppBottomSheet` |

### Budget
| File | Action |
|---|---|
| `budget/budget_view.dart` | List of category cards using `AppCard` |
| `budget/category_budget_tile.dart` | `AppCard` with `AppLinearProgress` for spent/limit |
| `budget/add_budget_sheet.dart` | Wrap with `AppBottomSheet` |

### History
| File | Action |
|---|---|
| `history/treasury_history_view.dart` | List of monthly summaries — `AppListTile`s |
| `history/monthly_summary_card.dart` | `AppCard`; income/expense/net in DM Mono |
| `history/monthly_summary_detail_view.dart` | `AppPageScaffold` + `AppSection`s |

---

## UX Direction

### Money Display
- All amounts in **DM Mono** via `AppNumberDisplay` — fixed-width digits
- Currency symbol typeset slightly smaller / lighter (use textStyle slot on `AppNumberDisplay`)
- Negative amounts: `AppColors.error` / theme `error` color, prefixed with `−` not `-(  )`

### Category Colors
- Keep existing finance category palette as fill colors
- Always pair fill with a 1px theme-aware border so light mode stays legible
- Pie chart segments use the same palette

### Lists
- Transaction rows: `AppListTile`
  - Leading: `AppIconBadge` (category icon, tonal fill in category color)
  - Title: merchant / description
  - Subtitle: category · date
  - Trailing: amount via `AppNumberDisplay` (DM Mono — red if expense, green if income)
  - `onDelete` for swipe-to-delete (replaces ad-hoc `Dismissible` in bill / installment / receivable / transaction tiles); confirms via `AppConfirmDialog`
- Long-press → `AppActionSheet` with Edit / Split / Duplicate / Delete (delete `isDestructive`)

### Charts
- All custom-painter charts (pie, bar, line, calendar heatmap) accept color params from theme — no hardcoded hex
- Chart wrappers live inside `AppCard` for consistent padding + elevation
- Category palette stays as fills; pair every fill with a 1px theme `outlineVariant` border for light-mode legibility
- Calendar heatmap (`spending_calendar.dart`): cell colors interpolate from `colorScheme.surfaceContainerLow` → `colorScheme.primary` based on intensity
- **Not introducing `fl_chart`** — existing custom painters stay; this plan only themes them

### Sheets
- All add/edit forms via `AppBottomSheet` with consistent header (title + close)
- Save action = `AppPrimaryButton`
- Destructive action (delete) = `AppDestructiveButton`

### Empty States
- Every list (no transactions / no bills / no budgets / no history): `AppEmptyState` with relevant icon and CTA

---

## Design-System Widgets Consumed

`AppPageScaffold` (dashboard root uses `.large`) · `AppSection` · `AppCard` · `AppListTile` (with `onDelete`) · `AppSelectableTile` · `AppIconBadge` · `AppNumberDisplay` · `AppLinearProgress` · `AppStatPill` · `AppBadge` · `AppTextField` · `AppSegmentedControl` · `AppBottomSheet` · `AppActionSheet` (long-press menus) · `AppPrimaryButton` · `AppSecondaryButton` · `AppDestructiveButton` · `AppConfirmDialog` · `AppEmptyState` · `AppErrorState`

---

## Acceptance Criteria

- [ ] Every dashboard widget renders inside an `AppCard` (no custom `Container` boxes)
- [ ] All list rows use `AppListTile`
- [ ] All sheets use `AppBottomSheet`
- [ ] All amounts use `AppNumberDisplay` (DM Mono)
- [ ] Charts read colors from `Theme.of(context)`; no hardcoded hex
- [ ] Both light and dark modes render every screen correctly
- [ ] Negative/positive amounts use semantic theme colors (error/primary or success)
- [ ] Empty states present on ledger, bills, budget, history

---

## Out of Scope

- Finance math / category logic / installment calculations (presenters untouched)
- Adding new chart types
- New transaction fields or schema changes
- Calendar heatmap algorithm changes
