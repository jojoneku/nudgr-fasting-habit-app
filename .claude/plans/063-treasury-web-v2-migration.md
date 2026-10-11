# Plan 063 — Treasury Web v2: migrate to the redesign

> Status: Phases 0–10 DONE on `feat/web-v2` · Phase 11 = CI flag flip in the `feat/web-v2` PR; deleting the pre-v2 pages is a follow-up PR after one stable release · Owner: Treasury web · Authored: 2026-10-10
> Design: private canvas **Treasury Web Redesign** (https://claude.ai/artifact/3tkCmCGcoJck3JEpJunngC) · tokens: **Nudgr Design System** (https://claude.ai/artifact/5JRAey8QH6AgTKjS87EmMF)
> Builds on: Plan 042 (web companion), Plan 050 (desktop shell), Plan 056 (Nudgr tokens)
> Audit that drives it: the web inventory of 2026-10-10 (31 code-level UX problems, listed in §9)

## 1. Goal

Replace the Treasury web UI (`lib/views/web/`) with the redesign on the canvas, page by page, **without losing a feature and without a day when the deployed site is half old and half new**. Every presenter, model and storage key stays as it is. This is a view-layer migration.

The redesign removes **one** feature from the web at the owner's request: the **Cart** page. It stays in the phone app and in the narrow (< 840 dp) web layout, which still mounts the mobile `TreasuryModuleView`.

## 2. Ground rules

1. **Views only.** Nothing under `lib/presenters/`, `lib/models/` or `lib/services/` changes, with two named exceptions: a shared budget-status threshold constant (§6, Phase 6) and a `WebDest` enum (§6, Phase 1). No storage key changes, so the finance `data_version` guard (PR #703) is not bumped.
2. **Behind a build flag until the end.** `const bool kWebV2 = bool.fromEnvironment('WEB_V2');` in `lib/views/web/web_flags.dart`. `_TreasuryWebHome` builds the v2 shell and v2 pages when the flag is on, the old ones when it is off. CI builds without the flag until the final phase, so every PR can merge to `dev` (which auto-promotes to `main` and deploys) with the live site unchanged.
3. **Old files are not edited.** New pages live beside the old ones (`web_dashboard_page_v2.dart`, …). The old files are deleted in the last phase. This keeps every PR a pure addition and makes rollback a flag flip.
4. **Parity is tested, not promised.** Every action on the canvas gets a stable `ValueKey` (`WebKeys.ledger.addTransaction`, …). A parity test per page asserts each key is present with seeded data. A button that disappears fails CI.
5. **One PR per phase, base `dev`,** Conventional Commits, `dart format` before push, Flutter tests green.
6. **Theme-aware colors only** (CLAUDE.md rule 7). The canvas hex values map to Nudgr tokens; the code reads `Theme.of(context)` and `context.appColors`. Light mode must work on every page.

## 3. What the canvas changes, per page

| Page | Keeps | Moves | Drops |
|---|---|---|---|
| Shell | 7 destinations, theme toggle, sync status, email, sign out, Nudgy | Nudgy launcher → header button; on Dashboard a fixed right rail. Sign out → account row. Nav grouped (Overview · Money · Plan · Review). 1200 px content width applied. | Topbar title (duplicate of page header). **Cart destination (desktop only).** |
| Dashboard | Net worth hero + sparkline, net cash flow, liquid cash, total assets, 6 outlook figures, accounts + All N, 3 trend charts, cash flow, budget health, credit Pay now, donut, savings goals | Outlook → one vertical statement with signed amounts. 3 charts → one Trends card with a switch. Position stats → inside the hero. | "Can I afford it?" is **not** added (owner's call). |
| Ledger | Month stepper, all-months search, filters & sort, active chips, Add transaction, Scan receipt, draft row, inline editing, selection bar, delete + undo, running balance, transfer badge | Scan receipt → toolbar. Notes shown under the description. Row ⋯ menu replaces hover-only delete. Footer hint → month totals. | Green/red column washes. |
| Bills | Due-soon hero, Mark paid, edit, reminder, all totals, coming up, credit cards + Pay now, upcoming, set-asides, by account, receivables, installments, paid, batch select, every Add | 5 list cards → tabs in one list. 4 Add buttons → one Add ▾ menu. Totals → side column. Credit cards → under the list. | A bill shown 3 times. |
| Budget | Pace ring, spent/allocated/left, pace pill, Manage groups, month stepper, editable Allocated, group dropdown, status badges, remove, add row, donut | Rows grouped with subtotals. Donut beside the ring. | 4-tile strip (repeated the hero). |
| History | Live card, 5 period stats, cash flow trend, cumulative savings, ending cash, monthly table, spending by category, month detail | Live card full width; 5 stats as one row; the two small charts beside the table. | — |
| Setup | 4 stats, grouped table, inline type, credit limit + available, add pocket/goal, edit, delete, Add account, categories table | Accounts / Categories → tabs. Credit limit + Available → one "Credit / target" column. | "—" in empty credit cells. |
| Goals | Add goal, Start again, savings accounts | Mobile `GoalsSavingsScreen` → a web page: header, hero, goal card grid, savings table. | Floating button. |
| Login | Google sign-in, error toast | Split layout with a brand panel; theme toggle. | — |
| Forms (17) | Every field of every dialog | One dialog language. Optional fields under "More options". **Settle** replaces Settle + 2 Quick pay + Batch settle. | Three form styles; duplicate dialogs. |

## 4. Affected files

| File | Action | Phase |
|---|---|---|
| `lib/views/web/web_flags.dart` | Create — `kWebV2` | 1 |
| `lib/views/web/web_keys.dart` | Create — `ValueKey` registry for parity tests | 1 |
| `lib/views/web/design/web_dest.dart` | Create — `WebDest` enum + mobile tab mapping | 1 |
| `lib/views/web/design/web_theme.dart` | Modify — chip, snackBar, button, dialog themes; `secondary` no longer the warning orange | 0 |
| `lib/views/web/widgets/web_shell.dart` | Modify — v2 branch: grouped nav, header actions slot, right-rail slot, max width | 1 |
| `lib/views/web/widgets/web_nudgy_dock.dart` | Modify — launcher as a header button; `NudgyRail` (Dashboard) and `NudgyPanel` (other pages) share `NudgyController` | 1 |
| `lib/views/web/widgets/web_page_header_v2.dart` | Create — title, subtitle, actions, month stepper slot | 2 |
| `lib/views/web/widgets/web_dialog.dart` | Create — `WebDialog`, `WebField`, `WebFold`, `WebDialogFooter` | 2 |
| `lib/views/web/widgets/web_tabs.dart` | Create — list tabs with counts | 2 |
| `lib/views/web/widgets/web_stat_strip.dart` | Create — even stat row; replaces the 4 hand-rolled KPI grids | 2 |
| `lib/views/web/widgets/web_row_menu.dart` | Create — ⋯ menu for rows | 2 |
| `lib/views/web/widgets/web_settle_dialog.dart` | Modify — single, batch and card modes; absorbs `web_quick_pay_dialog.dart`, `web_batch_settle_dialog.dart` and `_WebQuickPayDialog` | 5 |
| `lib/views/web/pages/*/web_*_page_v2.dart` | Create — one per page | 3–9 |
| `lib/views/web/pages/goals/web_goals_page.dart` | Create — new web page | 9 |
| `lib/views/web/web_login_view.dart` | Modify | 10 |
| `lib/views/web/treasury_web_app.dart` | Modify — flag switch; `WebDest`; drop Cart from the desktop list | 1, 11 |
| `lib/views/web/pages/more/web_more_page.dart` | Modify — add a Setup entry (fixes "Setup unreachable below 840") | 1 |
| `lib/presenters/budget_presenter.dart` | Modify — `kBudgetWatchThreshold = 0.75` exported; dashboard reads it | 6 |
| `lib/views/web/dev/preview_seed.dart` | Modify — seed 23 accounts, 11 bills, 8 goals, 8 installments (shapes from the real data) | 0 |
| `test/views/web/*_v2_test.dart` | Create — parity + behavior tests per page | 3–10 |
| `.github/workflows/*.yml` (deploy_web) | Modify — add `--dart-define=WEB_V2=true` | 11 |
| `docs/treasury_web_spec.md` | Modify — status line (it still says PLANNED), §7 layout notes | 11 |
| Old `web_*_page.dart`, `web_quick_pay_dialog.dart`, `web_batch_settle_dialog.dart`, `web_tile_flow.dart`, `web_section.dart` | Delete | 11 |

## 5. Interface definitions

```dart
// lib/views/web/web_flags.dart
const bool kWebV2 = bool.fromEnvironment('WEB_V2');

// lib/views/web/design/web_dest.dart — replaces the shared int index
enum WebDest { dashboard, ledger, bills, budget, history, goals, setup }
extension WebDestX on WebDest {
  /// Index in the mobile TreasuryModuleView TabBar (< 840 dp). Setup → More.
  int get mobileTabIndex;   // dashboard 0, ledger 1, bills 2, budget 3, history 4, goals 6, setup 7 (More)
}

// lib/views/web/web_keys.dart — one key per canvas action; parity tests read these
abstract final class WebKeys {
  static const ledgerAddTransaction = ValueKey('web.ledger.addTransaction');
  static const ledgerScanReceipt    = ValueKey('web.ledger.scanReceipt');
  static const billsAddMenu         = ValueKey('web.bills.addMenu');
  static const billsTabUpcoming     = ValueKey('web.bills.tab.upcoming');
  // … one per action on the canvas (≈ 60)
}

// lib/views/web/widgets/web_dialog.dart
class WebDialog extends StatelessWidget {        // 520 px, radius 24, header, body, footer
  const WebDialog({required this.title, this.subtitle, required this.body,
    required this.primary, this.secondary, this.destructive, this.width = 520});
}
class WebField extends StatelessWidget {         // uppercase label above a 46 px control
  const WebField({required this.label, this.optional = false, required this.child, this.helper, this.error});
}
class WebFold extends StatefulWidget {           // "More options" / titled fold with an optional switch
  const WebFold({required this.title, this.subtitle, this.toggle, this.initiallyOpen = false, required this.child});
}

// lib/views/web/widgets/web_settle_dialog.dart — one dialog for every settle path
enum SettleKind { bill, receivable, setAside, installment, cardPayment }
Future<SettleResult?> showWebSettleDialog(BuildContext context, {
  required SettleKind kind,
  required List<SettleTarget> targets,   // 1 = single, >1 = batch (the batch bar)
  required List<FinancialAccount> accounts,
});
// Returns the same SettleResult the presenters already consume; the two quick-pay
// dialogs and the batch dialog are deleted once every call site uses this.

// lib/views/web/widgets/web_nudgy_dock.dart
class NudgyController { bool open; double width; bool get isRail; }  // unchanged API + isRail
class NudgyHeaderButton extends StatelessWidget {}   // "Ask Nudgy" in the page header
class NudgyRail extends StatelessWidget {}           // Dashboard right column, always open ≥ 1280
```

## 6. Implementation order (one PR each)

### Phase 0 — Prep (no visual change) · `chore/web-v2-prep`
1. [ ] `web_theme.dart`: add chip, snackBar, button and dialog sub-themes to match mobile; move the warning orange off `secondary` (it makes selected chips brown). Verify the old pages still render.
2. [ ] Extend `preview_seed.dart` with the real shapes: 23 accounts (7 liquid incl. one overdrawn, 8 goals, 6 credit lines, 1 investment), 11 October bills (4 unpaid), 2 receivables, 7 set-asides, 8 installments, 9 monthly summaries. Amounts are illustrative, names real.
3. [ ] Write `docs/web_parity_checklist.md`: every action per page, copied from the audit inventory (§3 of this plan is the summary). This is the acceptance list for each later phase.
4. [ ] Tests: the 10 existing `test/views/web/*` stay green.

### Phase 1 — Flag, destinations, shell · `feat/web-v2-shell`
1. [ ] `kWebV2`, `WebDest`, `WebKeys`.
2. [ ] `_TreasuryWebHome`: when `kWebV2`, build the desktop list **without Cart** and route by `WebDest`; the narrow layout keeps `TreasuryModuleView` with Cart. `WebMorePage` gets a Setup entry.
3. [ ] `WebShell` v2: grouped nav, account row (email + Sign out), sync row, theme toggle in the nav foot; header actions slot; optional right-rail slot; `WebBreakpoints.content` applied; no topbar title.
4. [ ] Nudgy: `NudgyHeaderButton` on every page; `NudgyPanel` slide-over everywhere except Dashboard, where `NudgyRail` is a fixed column ≥ 1280 and a slide-over below. One header row (drop `AiChatBody`'s second row via `showEntryLabel:false` + a `compactHeader` flag). Input hint "Log a transaction or ask about your money…".
5. [ ] Floating buttons removed from the shell (the Ledger receipt FAB and the Goals FAB go in their phases).
6. [ ] Tests: `web_shell_v2_test` (7 destinations, no Cart ≥ 840, Cart present < 840, Setup reachable < 840 via More), `web_nudgy_dock_test` extended for rail vs panel.

### Phase 2 — Shared kit · `feat/web-v2-kit`
1. [ ] `WebPageHeaderV2`, `WebDialog` + `WebField` + `WebFold` + `WebDialogFooter`, `WebTabs`, `WebStatStrip`, `WebRowMenu`, `WebListRow`.
2. [ ] One date-picker range constant (`kWebDateRange`, 2020–2035) and one confirm-dialog style (red filled primary, Cancel ghost).
3. [ ] Tests: `web_design_system_test` extended: dialog radius 24, field height 46, focus border 1.5 px primary, tab label never wraps, stat strip gives equal widths.

### Phase 3 — Dashboard · `feat/web-v2-dashboard`
1. [ ] `WebDashboardPageV2`: hero (net worth + 3 stats + sparkline) + outlook statement; accounts table; cash flow; budget health; Trends card with `WebSegmented` (net worth · income vs expenses · daily spending — reuse the three existing chart widgets, one visible at a time); donut; credit; savings goals. Right rail = Nudgy + Coming up.
2. [ ] Reuse `WebAccountInventoryDialog` for "All N".
3. [ ] Remove the `_MasonryFlow` RenderBox and the private `_accountCategoryLabel` (use `design/account_category_label.dart`).
4. [ ] Budget-health badges read the shared threshold (Phase 6 lands the constant; until then keep 0.85 and note it).
5. [ ] Tests: parity keys; outlook arithmetic renders the six presenter values; trends switch shows one chart.

### Phase 4 — Ledger · `feat/web-v2-ledger`
1. [ ] `WebLedgerPageV2`: header with stepper, Scan receipt and Add transaction in the toolbar; search; Filters & sort popover (reuse `_FiltersAndSort`, moved to a shared file); chips; selection bar; grid with Notes under Description; row ⋯ menu (Edit, Duplicate, Split into installments, I'll get this back, Delete+undo); footer month totals.
2. [ ] Keep: draft row, inline editors, column resize, transfer badge → edit dialog, bulk delete confirm, 6 s undo (via `AppToast.action`, not `ScaffoldMessenger`).
3. [ ] Add transaction dialog onto `WebDialog` with `WebFold` for installments and More options (notes, reimbursable). Same `LedgerPresenter` calls.
4. [ ] Tests: `web_ledger_filters_test` adapted; new: notes visible, row menu actions present, Scan receipt key in toolbar, footer totals equal presenter month totals.

### Phase 5 — Bills + Settle · `feat/web-v2-bills`
1. [ ] `showWebSettleDialog` gains `targets` (batch) and `SettleKind.cardPayment`. Port the four `showWebBatchSettleDialog` call sites and the two quick-pay call sites (dashboard credit card, bills credit card) to it. Delete `_WebQuickPayDialog`; keep the old shared files until Phase 11.
2. [ ] `WebBillsPageV2`: header with stepper + Add ▾ (Bill / Receivable / Set-aside / Installment) ; hero (first due-soon bill; the others move into the list's "Due soon" group at the top); tabbed list (Upcoming · Set-asides · Receivables · Installments · Paid) with the existing `WebRowSelection` batch bar per tab; credit cards & lines card; side column (This month, By account, Coming up).
3. [ ] Bill, Receivable, Set-aside and Installment dialogs onto `WebDialog`; optional fields under More options; "Recurring: which ones?" and "Delete installment?" onto the shared confirm.
4. [ ] Tests: `web_bills_batch_selection_test`, `web_batch_settle_test`, `web_settle_dialog_test` adapted to the unified dialog; new: each tab's count equals the presenter list length; Add ▾ opens all four; a bill appears in exactly one place besides the hero.

### Phase 6 — Budget · `feat/web-v2-budget`
1. [ ] `kBudgetWatchThreshold` in `budget_presenter.dart` (0.75); the dashboard and the budget page both read it (fixes the 75 % vs 85 % disagreement).
2. [ ] `WebBudgetPageV2`: hero ring + donut side by side; grouped table with subtotal rows; editable Allocated cells; add row with Expense/Savings segment and "New category…"; Manage groups dialog onto `WebDialog`.
3. [ ] Over-budget rows use the warning tone with "Over by ₱X" text (design-system UX rule), not red alone.
4. [ ] Tests: `web_budget_add_row_test`, `web_budget_savings_row_test` adapted; new: group subtotals equal the sum of their rows; status pills never wrap at 1280.

### Phase 7 — History · `feat/web-v2-history`
1. [ ] `WebHistoryPageV2`: live card full width; `WebStatStrip` of 5; cash flow trend; table + the two sparkline cards; spending by category; month detail onto `WebDialog` with "Open in Ledger" (sets the ledger month and navigates).
2. [ ] Replace the private `_parseHex` with `resolveSliceColor` so category colors match the other pages.
3. [ ] Layout decisions from `LayoutBuilder`, not window width (Nudgy open must not squeeze the pair).
4. [ ] Tests: table rows equal summaries; month detail opens from a row and from the live card.

### Phase 8 — Setup & Accounts · `feat/web-v2-setup`
1. [ ] `WebSetupPageV2`: header with Accounts / Categories tabs; stat strip; grouped table with the single "Credit / target" column; account form onto `WebDialog` with the statement & payment fold; categories table + add row + icon picker unchanged in behavior.
2. [ ] Replace the private `_hexColor` and the Tailwind `kCategoryPalette` with the Nudgr category palette (`category_colors.dart`).
3. [ ] Delete account confirm: if the account has transactions, offer Archive (the presenter's existing rule decides; the dialog only explains it).
4. [ ] Tests: `web_account_inventory_test` adapted; new: credit column filled only on credit rows; tabs switch content; "+" on a parent opens the pocket/goal form.

### Phase 9 — Goals · `feat/web-v2-goals`
1. [ ] `WebGoalsPage` (new, web-only): header with Add goal; hero; goal card grid; savings & investments table; funding-model note; Start again confirm. Uses the same `TreasuryDashboardPresenter`/`LedgerPresenter` getters `GoalsSavingsScreen` uses today.
2. [ ] Add goal dialog creates the goal account and the Savings budget row the same way the mobile sheet does (call the same presenter method; do not re-implement).
3. [ ] Tests: cards equal goal accounts; "Set a monthly amount" opens the set-aside dialog.

### Phase 10 — Forms pass + Login · `feat/web-v2-forms`
1. [ ] Walk every dialog against the canvas: field order, More options content, button labels, destructive placement. Fix stragglers (statement breakdown onto `WebDialog`, receipt dialog, delete confirms).
2. [ ] Login split layout with the theme toggle.
3. [ ] Keyboard: Tab order through each dialog; Enter submits; Esc closes. Screen reader: dialog titles as `semanticsLabel`.
4. [ ] Tests: one smoke test per dialog (opens, required-field error shows, primary submits with seeded data).

### Phase 11 — Flip, clean up, ship · `feat/web-v2-ship`
1. [ ] Full parity walk of `docs/web_parity_checklist.md` on `localhost:8090` with `--dart-define=PREVIEW_SEED=true --dart-define=WEB_V2=true`, at 1280, 1440 and 1920 px, Nudgy open and closed, dark and light, and at 800 px (narrow layout unchanged).
2. [ ] CI `deploy_web`: add `--dart-define=WEB_V2=true`. Keep the flag for one release so a revert is one line.
3. [ ] Delete the old pages and the dead kit (`web_tile_flow.dart`, `web_section.dart`, `web_quick_pay_dialog.dart`, `web_batch_settle_dialog.dart`, `WebStatTile.accent/emphasize`, `WebCard.onSurface`), drop `kWebV2` in a follow-up PR after the release is stable.
4. [ ] `docs/treasury_web_spec.md`: status → SHIPPED (it still says PLANNED), §7 updated with the v2 layout; `docs/design-reference/README.md` points at the canvas.

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| A feature is lost in the rewrite | `WebKeys` parity tests per page + the checklist walk in Phase 11. The audit inventory is the source list. |
| The live site shows a half-migrated UI | `kWebV2` build flag; CI flips it only in Phase 11. Old files untouched until then. |
| The shared int index breaks the narrow layout when Cart leaves the desktop list | `WebDest` enum with an explicit `mobileTabIndex`; tests at 800 px. |
| Unifying Settle changes a presenter call by accident | `showWebSettleDialog` returns the same `SettleResult`; each ported call site keeps its presenter call; the three adapted tests cover single, batch and card modes. |
| Light mode regressions (the canvas is dark-first) | Every page reads tokens; `web_design_system_test` renders each v2 page in both themes and checks text contrast on card and screen with the design system's values (4.5:1 text, 3:1 fills). |
| Nudgy rail squeezes the Dashboard on small desktops | Rail only ≥ 1280 px; below that it is the slide-over; History and Dashboard use `LayoutBuilder`. |
| Wide tables (ledger ≥ 980 px, setup ≥ 820 px) overflow with Nudgy open | Tables scroll inside their card (`overflow-x`); the ledger drops the Balance column below 1100 px of content width, behind a "Show balance" toggle. |
| Chart widgets (`fl_chart`) differ from the canvas sketches | Keep the existing chart widgets; restyle axes, labels and colors only. The canvas charts are a target, not a spec. |
| Firebase deploy serves a stale `main.dart.js` | Existing cache-busting in `deploy_web`; verify the build hash after Phase 11. |
| The `.env` public asset is missing in a new worktree | Documented in memory; copy it before `flutter run`. |
| Dead code after the flip | Phase 11 deletes it; `flutter analyze` with `unused_element` must be clean. |

## 8. Acceptance criteria

- [ ] Every row of `docs/web_parity_checklist.md` passes on the v2 build at 1440 px, dark and light.
- [ ] The narrow (< 840 dp) layout is unchanged, Cart included, and Setup is reachable via More.
- [ ] `flutter test` green, including all `test/views/web/*` (10 adapted + the new v2 tests).
- [ ] No floating button overlaps another control on any page, Nudgy open or closed.
- [ ] Every page has one header (no duplicate title), the 1200 px content width, and the grouped nav.
- [ ] One Settle dialog; `_WebQuickPayDialog`, `web_quick_pay_dialog.dart` and `web_batch_settle_dialog.dart` are gone.
- [ ] One form style across all dialogs; the three old styles are gone.
- [ ] Budget "Watch" threshold is one constant read by both pages.
- [ ] `docs/treasury_web_spec.md` status is current.

## 9. Audit items this plan closes

From the 2026-10-10 inventory (numbers as listed there): 1 floating-button collisions · 2 duplicate page title · 3 unused 1200 px width · 4 inconsistent headers · 5 Nudgy double header · 6 History window-width layout · 7 mobile screens in the desktop shell · 8 Setup unreachable < 840 · 9–11 scattered radii and borders · 12 four KPI-grid implementations · 13 hard-coded font sizes · 14 inconsistent expense color · 15 threshold disagreement · 16 hard-coded hexes and two hex parsers · 17 web theme gaps · 18–23 Bills/Dashboard/Budget duplication · 24 two account-label definitions · 25 mixed feedback styles · 26 three form styles · 27 dense tables · 28 long dialogs · 29 microcopy instead of affordances · 30 hidden notes · 31 hover-only delete · 32–34 missing states and the bare login.

## 10. Out of scope

- The mobile Treasury module and the Hub.
- The "Can I afford it?" calculator (declined by the owner).
- Sheets export, CSV import, bank sync.
- Presenter refactors flagged in the finance audit (Rule-1 `build()` logic) — a separate plan.
