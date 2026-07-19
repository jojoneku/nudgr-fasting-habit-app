## Why

The Treasury Dashboard is the landing tab of the finance module and the next screen in the Nudgr
redesign after the Hub and Nutrition. Today the mobile dashboard opens with a plain cash-summary
banner and a dense 2×2 metric grid — it answers "what are my numbers" but never leads with the one
figure that frames everything (**net worth and its momentum**), and its cards predate the shipped
Nudgr tokens so it reads as a different app than the redesigned Hub. The locked-in reference
(`Nutrition Focus Treasury.dc.html`, Frame 1 · Dashboard) reframes the top of the screen into a
**NET WORTH hero with a sparkline**, a compact **cashflow strip** ending in "Projected spare", and a
glanceable **Accounts** list. This is a **restyle + reframe** of the existing dashboard — every
current card stays; the top of the screen is rebuilt to the reference and everything below is
re-skinned to Nudgr tokens. The web companion dashboard already mirrors this reference (Plan 050-A);
this change verifies and aligns it to the shipped tokens so mobile and web read as one system.

## What Changes

- **Add a NET WORTH hero** at the top of the mobile dashboard — a blue gradient card with the big
  net-worth figure, a trend pill (± % vs last month), a "+₱X this month" line, and a **sparkline**
  of the net-worth trend. Replaces the top slot of the current `CashSummaryBanner`. Reads
  `presenter.netWorth`, `presenter.monthNetCashFlow`, and `presenter.netWorthTrend()` — no new math.
- **Add a cashflow strip** below the hero — "{Month} cashflow" with "{N} days left", an income bar
  (green) and expense bar (red) sized to the month's inflow/outflow, and a **Projected spare** total
  in the domain accent. Reads `monthTotalInflow` / `monthTotalOutflow` / `forecastedNetBalance`.
- **Restyle the Accounts section** into the reference's row list — icon badge + name + type subtitle
  + balance, with a section header showing total liquid cash and a **"+N more accounts"** expander
  when there are more than a threshold (keeps the existing tap-to-edit and the Add-account FAB).
- **Re-skin the retained cards** to Nudgr tokens (rounded cards, accent usage, spacing) without
  changing their content or behavior: metric grid, spending analytics, category pie, upcoming bills,
  budget overview, goals & savings, credit section, held/external funds.
- **Add a greeting + "Synced" status header** matching the reference (greeting line + "Treasury"
  title + a sync-status pill), reusing existing sync state — no new sync plumbing.
- **Verify + align the web dashboard** (`web_dashboard_page.dart`) to the shipped Nudgr tokens and
  the reference; it already implements the hero/forecast/accounts structure, so this is a
  token/contrast pass, not a rebuild.
- Use **Material icons** (not Phosphor) and read all colors from `Theme.of(context)` /
  `context.appColors`, consistent with the shipped Nudgr tokens and the Hub/Nutrition redesigns.

Non-breaking. No presenter, model, service, or navigation entry point changes; `TreasuryDashboardView`
keeps its constructor and its mount point inside `TreasuryModuleView` is unchanged.

## Non-goals

- **Not the other Treasury tabs.** Ledger, Bills, Budget, History, and Cart are captured for
  **later** increments of the Treasury redesign — each its own change and PR. This change touches
  only the Dashboard tab (and its web equivalent).
- **No presenter/business-logic rewrite.** `TreasuryDashboardPresenter` keeps its public API; this
  change is view-layer + (at most) small additive computed getters (e.g. a net-worth month-over-month
  delta) if not already present. Net-worth math, forecasting, cash-flow classification, and
  persistence are untouched.
- **No data-model or storage changes**, no migration, no new dependencies (no Phosphor package — the
  Nudgr font/tokens already shipped).
- **Not the account-setup / add-account flow**, the goal-savings sheet, or the credit "Pay Now"
  path — those keep their current behavior; only their card styling is refreshed.

## Capabilities

### New Capabilities
- `treasury-dashboard`: The Treasury Dashboard tab — greeting + sync-status header, the NET WORTH
  hero (net worth, month-over-month trend pill, "this month" delta, sparkline), the cashflow strip
  (income/expense bars + "Projected spare"), the Accounts list (liquid-cash header, per-account rows,
  "+N more" expander, tap-to-edit, Add-account FAB), and the retained-and-reskinned analytics stack
  (metric grid, spending analytics, category breakdown, upcoming bills, budget overview, goals &
  savings, credit, held/external funds) with empty/loading states — on both mobile and the web
  companion, using theme tokens (no hardcoded per-mode colors).

### Modified Capabilities
<!-- None. openspec/specs/ contains only `hub`; there is no existing `treasury` capability, and no
     other capability's spec-level requirements change. Presenter additions (if any) are additive
     implementation details covered in design.md. -->

## Impact

- **New:** `lib/views/treasury/dashboard/` gets extracted Nudgr pieces — likely `net_worth_hero.dart`
  (hero + sparkline), `cashflow_strip.dart`, and an accounts-list widget with the "+N more" expander.
- **Modified:** `treasury_dashboard_view.dart` (new top section + re-skin + expander wiring),
  `cash_summary_banner.dart` / `metric_cards_grid.dart` / `account_card_widget.dart` and the other
  dashboard cards (token re-skin as needed), and `lib/views/web/pages/dashboard/web_dashboard_page.dart`
  (token/contrast alignment).
- **Presenter (additive only, if needed):** a net-worth month-over-month delta/percentage getter and
  a "days left in month" helper if not already derivable — no behavior change to existing getters.
- **Reuses (unchanged):** `TreasuryDashboardPresenter` and all its getters, `AppCard` /
  `AppSection` / `AppLinearProgress` / `AppEmptyState` / `AppNumberDisplay` from
  `views/widgets/system/`, the web design system (`web_widgets.dart`), Nudgr theme tokens,
  `finance_format.dart`, `StorageService`.
- **Deps:** none new. **Risk:** low — view-layer restyle over an unchanged presenter; the main risk
  is preserving every retained card and its states while re-skinning, verified against a
  card-inventory checklist in design.md.
