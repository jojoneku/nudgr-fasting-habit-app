# Plan 050 — Treasury Web Redesign (desktop-grade UI)

> Status: IN PROGRESS
> Parent spec: [docs/treasury_web_spec.md](../../docs/treasury_web_spec.md) · Builds on Plan 042 Phase 1 (shipped on `feat/042-treasury-web`)
> Branch: **`feat/042-treasury-web`** (foundation) + per-page agent worktrees → merged back. Own PR to `dev`.
> Authored: 2026-06-11

## Goal
Plan 042 Phase 1 mounts the **mobile** `TreasuryModuleView` (bottom tabs) in the browser — it works but
looks like a stretched phone. This plan replaces the ≥ 840 dp experience with a **desktop-grade web UI**:
a left sidebar shell, a **shadcn-inspired Dart design system**, a **tabular sheet-style ledger**, and a
**dashboard with real visualizations**. Below 840 dp the existing mobile views render unchanged (free
mobile-web parity).

**Stack decision:** Flutter web + a shadcn-*inspired* component kit written in Dart. shadcn/ui is React
and cannot run inside Flutter; we reproduce its visual language (bordered cards, restrained palette,
dense tables, hover affordances, generous whitespace) with `Theme.of(context)` tokens. One codebase, all
presenters reused, sync semantics intact.

---

## Architecture — two waves

### Wave 1 — Foundation (built directly on `feat/042-treasury-web`, committed before agents spawn)
The shared substrate every page depends on. Agents must **read** these, never fork them.

- **`fl_chart`** dependency added (web-compatible charting; replaces hand-rolled `CustomPaint` for web).
- **Design system** `lib/views/web/design/` + `lib/views/web/widgets/`:
  - `web_breakpoints.dart` — `WebBreakpoints.rail = 840`, content max-width `1200`, `WebInsets` (denser desktop spacing).
  - `web_card.dart` — `WebCard`: `surfaceContainerLow` fill, 1px `outlineVariant` border, `AppRadii.lg`, optional title/description/trailing header. The shadcn "card".
  - `web_section.dart` — `WebSectionHeader` (title + subtitle + trailing action).
  - `web_stat_tile.dart` — `WebStatTile` (label, big value, optional delta/sub, icon) for KPI strips.
  - `web_data_table.dart` — `WebDataTable<T>`: column config (label, numeric flag, flex, cell builder),
    sticky header, hover row highlight, zebra optional, right-aligned numerics, optional section group
    headers with subtotals, row `onTap`. The reusable sheet-grid primitive.
  - `web_badge.dart` — small status pill (paid/unpaid/over-budget/imminent).
  - `web_shell.dart` — `WebShell`: `NavigationRail` (extended, labels) left with 6 destinations + sync
    status + sign-out; content area constrained to `WebBreakpoints.content`, scrolls; theme-aware both modes.
- **Dashboard parity getters** in `TreasuryDashboardPresenter` (pure, mobile gets them too): `totalAssets`,
  `monthNetCashFlow`, `savingsRate`, `currentObligations`, `projectedSpareThisMonth`, and
  `AffordVerdict canAfford(double, {String? accountId})`. `netWorth` refactored to reuse `totalAssets`
  (behavior identical). Unit tests in `test/presenters/treasury_dashboard_parity_test.dart`.
- **Page stubs** `lib/views/web/pages/{dashboard,ledger,bills,budget,history,cart}/` — one folder per page,
  each exporting a `Web<Page>Page` widget that initially wraps the existing mobile view. Agents replace the
  body of their own folder only → disjoint files, no cross-agent write conflicts.
- **Shell wiring** in `treasury_web_app.dart`: `LayoutBuilder` → `WebShell` hosting the 6 page widgets at
  ≥ 840 dp; existing `TreasuryModuleView` below.

### Wave 2 — Pages (one agent each, parallel worktrees off the Wave 1 commit)
Each agent owns exactly one `lib/views/web/pages/<page>/` folder. Rules for every agent:
- Use Wave 1 components (`WebCard`, `WebDataTable`, `WebShell` context, `WebStatTile`, `fl_chart`).
- **Theme-aware colors only** — `Theme.of(context).colorScheme.*`, never `AppColors.*` (Rule 7).
- **No math/conditionals in `build()`** — read from the presenter; add getters to the presenter if needed
  (only the owning presenter, to avoid cross-agent conflicts).
- Card-on-background → `surfaceContainerLow`; card-on-card/sheet → `surfaceContainerHigh`.
- Reuse existing sheets/dialogs (e.g. `add_transaction_sheet.dart`) as **dialogs** on web for edits.
- Keep page-specific widgets inside the page's own folder; do **not** edit shared design-system files
  (flag if a shared addition is genuinely needed).
- Verify with `flutter analyze` on the page folder + `dart format`.

---

## Per-page sub-plans (agent briefs)

### 050-A — Dashboard
Reproduce the sheet's DASHBOARD using horizontal space and visuals. Bands top→bottom:
1. **Position strip** — `WebStatTile`s: Net Worth (hero), Liquid Cash, Total Assets, Current Obligations.
2. **This Month** — Income, Expenses, Net Cash Flow, **Savings Rate** (gauge/ring), Projected Spare,
   Outstanding Bills, Outstanding Budget, Receivables.
3. **Visuals row** — `fl_chart`: expense-by-category **donut** (`categorySpendThisMonth`), last-30-day
   spend **line/bar** (`lastNDaysSpending(30)`), budget-by-group **horizontal bars**
   (`budgetAllocatedByGroup`/`budgetSpentByGroup`).
4. **Accounts & tools** — per-account balance `WebDataTable` (liquid + credit available-limit rows, "yours
   vs held" via `heldAmountByAccountId`) and a **"Can I afford it?"** `WebCard`: amount field + account
   dropdown → `presenter.canAfford(...)` verdict line (tier copy strings live in the view).
Uses the Wave 1 parity getters. 1-col reflow < 840 dp falls back to the mobile dashboard.

### 050-B — Ledger (chat is KEPT; tabular is ADDED)
**Do NOT remove the chat-based logging.** Add a **view-mode toggle** (segmented control in the page
header): **Chat** (existing `LedgerView`, embedded) ⇆ **Table** (new, sheet-style).
- **Table mode** = the sheet's "Detailed Records": `WebDataTable` columns Date · Account · Description ·
  Category · Inflow · Outflow · **running Balance** (computed per filtered account scope, presenter-derived,
  never stored) · Notes. Month section headers with inflow/outflow subtotals. Filters: month / account /
  category (covers the sheet's "Filtered View").
- **Inline logging like sheets**: an "add row" at the top (or empty trailing row) that writes via
  `presenter.addTransaction(...)`; row click → `add_transaction_sheet.dart` as a dialog for edit
  (`updateTransaction`) / delete. Running-balance + filter logic goes in `LedgerPresenter` getters, not `build()`.

### 050-C — Bills & Receivables
Two-pane ≥ 840 dp: left = list (bills + receivables + installments), right = detail/edit. `WebDataTable`
for each section (Name · Type · Amount · Due · Status `WebBadge` · Notes) mirroring the sheet's
"Bills & Receivables". Mark-paid / mark-received inline. Reuse `add_bill_sheet`/`add_receivable_sheet`/
`add_installment_sheet` as dialogs.

### 050-D — Budget
Allocation overview with `fl_chart` group bars (allocated vs spent by `BudgetGroup`), per-category
`WebDataTable` (Category · Allocated · Spent · Remaining · % bar), over-budget `WebBadge`. Reuse
`add_budget_sheet` as a dialog.

### 050-E — History
Monthly-summary `WebDataTable` (Month · Income · Expenses · Net · Savings rate) + a trend `fl_chart`
(net cash flow over months). Row click → month detail (reuse `monthly_summary_detail_view`).

### 050-F — Cart
Desktop grocery-cart layout: items `WebDataTable` (Item · Qty · Unit · Price · Line total), running-total
`WebStatTile` strip (confirmed / estimated / unpriced), budget meter, checkout → Ledger. Reuse existing
grocery sheets as dialogs.

---

## Affected files (Wave 1)
| File | Action |
|---|---|
| `pubspec.yaml` | add `fl_chart` |
| `lib/presenters/treasury_dashboard_presenter.dart` | parity getters + `AffordVerdict`; refactor `netWorth` |
| `test/presenters/treasury_dashboard_parity_test.dart` | new |
| `lib/views/web/design/web_breakpoints.dart` | new |
| `lib/views/web/widgets/web_card.dart`,`web_section.dart`,`web_stat_tile.dart`,`web_data_table.dart`,`web_badge.dart`,`web_shell.dart` | new |
| `lib/views/web/pages/<6 folders>/web_*_page.dart` | new stubs (agents fill in Wave 2) |
| `lib/views/web/treasury_web_app.dart` | shell wiring (breakpoint → WebShell) |

## Risks
| Risk | Mitigation |
|---|---|
| 6 agents diverge in look | Wave 1 design system is the single source of visual truth; agents read-only it |
| Cross-agent write conflicts | One folder per agent; worktree isolation; shared files frozen in Wave 1 |
| `build()` logic creep | Agents add getters to their owning presenter; reviewer checks Rule 1 |
| Merge friction | Disjoint page folders → clean merges onto the Wave 1 commit |
| Web chart perf | `fl_chart` is canvas-based and fine for these sizes; data is monthly-bounded |

## Acceptance
- [ ] ≥ 840 dp: sidebar shell, all 6 pages redesigned, consistent design system, both themes, no `AppColors.*`.
- [ ] Ledger has **both** Chat and Table modes; Table logs/edit/deletes via the presenter with running balance.
- [ ] Dashboard shows every §4 line-item + working "Can I afford it?" + charts.
- [ ] < 840 dp unchanged (mobile views); mobile app build/tests unaffected; `flutter build web` green.
