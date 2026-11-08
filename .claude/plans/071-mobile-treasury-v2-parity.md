# Plan 071 — Mobile Treasury: fix the scan bugs, then bring the web v2 ideas over

> Status: IN PROGRESS (Phase 0 merged PR #826; Phase 1 built 2026-11-08) · Authored: 2026-11-08 · Owner: Treasury mobile
> Builds on: Plan 063 (Treasury web v2), Plan 056 (Nudgr tokens)
> Source: the 2026-11-08 scan that compared each web v2 page with its mobile counterpart (Dashboard, Ledger, Bills, Budget, History, Setup, Goals). Every bug in §3 Phase 0 was checked by hand in the code.

## 1. Goal

The web Treasury got a full redesign in Plan 063. The mobile Treasury module did not. The scan found three kinds of gaps:

1. **Bugs on mobile** that web v2 does not have (a transfer delete that breaks balances, pay sheets that hide save errors, false delete copy, a missing validator, a wrong minus sign).
2. **Drift** between the two apps: different budget thresholds, labels, colors and helpers. Mobile keeps private copies of logic that now lives in `lib/views/web/`.
3. **Design ideas** from v2 that make the phone better: each bill in one place, one settle sheet, an outlook statement, row actions, notes in the list, a "More options" fold.

This plan fixes 1, removes 2, and ports the parts of 3 that fit a phone. It does **not** copy desktop-only ideas (see §9).

**Rule for every phase:** when web v2 computes something in a view (bill sorting, budget status, goal figures, ledger search), move it to the presenter first. Then both apps read the presenter. Do not copy web view logic into a mobile view. That copies a rule-1 break into a second place.

## 2. Ground rules

1. **No storage key changes.** No model field changes. The finance `data_version` guard is not bumped.
2. **One PR per phase,** base `dev`, Conventional Commits, `dart format` and `flutter analyze` clean, Flutter tests green.
3. **Theme-aware colors only** (CLAUDE.md rule 7). Every changed widget works in light and dark.
4. **Rule 8 and 9 hold.** New getters go on the presenter that owns the data. Mobile and web both read the same getter. New cross-presenter wiring goes in `TreasuryPresenters`.
5. **Web follows when a helper moves.** When a phase moves logic out of a web view into a presenter or `lib/utils/`, the web v2 page switches to it in the same PR. Then there is one copy.
6. **Phase 0 ships alone and first.** It is bug fixes only, so it is easy to review and safe to release.

## 3. Phases (implementation order)

### Phase 0 — Bug fixes · `fix/mobile-treasury-scan-bugs` · Effort S

| # | Bug | Where | Fix |
|---|---|---|---|
| 0.1 | Delete from the edit sheet removes only 1 leg of a transfer. The partner leg stays, and the 2 account balances go out of step. It also has no Undo. | `lib/views/treasury/ledger/add_transaction_sheet.dart:606-620` calls `LedgerPresenter.deleteTransaction` | Call `deleteTransactionOrGroup`, close the sheet, then show `AppToast.action` with Undo → `restoreTransactions(removed)`. Same path as swipe-delete (`ledger_view.dart:1209-1218`). See open question Q3 about the confirm. |
| 0.2 | Pay sheets show nothing when a save fails. | `_MarkBillPaidSheet`, `_MarkReceivedSheet`, `_MarkExpensePaidSheet`, `_MarkInstallmentPaidSheet` (`bills_receivables_view.dart` ~1555–2190), `batch_settle_sheet.dart`, `shared/quick_pay_sheet.dart:76-92` | Add `catch` → `AppToast.error('Could not save: …')`, keep the sheet open. Phase 5 replaces these sheets, but this fix ships now because Phase 5 is large. |
| 0.3 | `formatPeso(-1234)` renders `₱-1,234.00`. The Next Month card on the same screen shows `−₱1,234.00`. | `metric_cards_grid.dart:57, 99`, `cashflow_strip.dart:261` | Add `formatPesoMinus` to `lib/utils/finance_format.dart` (§4). Use it at these call sites. Replace `NextMonthForecast._signedPeso` (`treasury_dashboard_presenter.dart:151`) and web `_signedNegative` (`web_dashboard_page_v2.dart`) with it. |
| 0.4 | The account delete dialog says "permanently remove … cannot be undone". The presenter refuses when the account has transactions, so the text is false. It never mentions Archive. | `account_setup_view.dart:324-365` | Use the shared delete copy from Phase 1 (move it in this PR if Phase 1 is not merged yet). Map a refused delete to the shared error text. |
| 0.5 | Credit Limit has no validator. `1.2.3` is saved as `null` with no warning. | `account_setup_view.dart:1053-1062`, parse at `:241-243` | Add the same validator web uses (`web_account_form_dialog_v2.dart:256`): empty is allowed, otherwise a positive number. *Built note:* the mobile `AmountInputFormatter` already blocks typing `1.2.3`; the gap that remained was a lone `.`, which the validator now rejects. The validator moved to `lib/utils/account_form_rules.dart` as `optionalAmountValidator`. |

Tests:
- `ledger_presenter` test: deleting a transfer leg through the edit-sheet path removes both legs and restores both on Undo.
- Widget test: `quick_pay_sheet` with a presenter that throws shows the error toast and keeps the sheet open.
- Unit test for `formatPesoMinus` (negative, zero, positive).
- Widget test: account form rejects `1.2.3` in Credit Limit.

### Phase 1 — Shared helpers out of `lib/views/web/` · `refactor/treasury-shared-helpers` · Effort S

Today mobile keeps private copies of things web v2 already has. Move each one to one shared place, and point both apps at it.

| Today (web) | Today (mobile copy) | Move to |
|---|---|---|
| `views/web/pages/setup/web_account_form_rules.dart` (colors, category lists, validators) | `account_setup_view.dart:14-25` `_colorOptions`, category lists; `:1185-1189` `_positiveAmountValidator` | `lib/utils/account_form_rules.dart` (drop the `web`/`kWeb` prefixes) |
| `views/web/design/account_category_label.dart` | `account_setup_view.dart:751-763`, `dashboard_accounts_list.dart:195-209` (casing differs: "Time deposit"), `web_dashboard_page.dart:824` ("E-wallet", v1 page, leave it) | `lib/utils/account_category_label.dart` |
| `webAccountDeleteMessage`, `webAccountDeleteError` (`web_account_form_dialog_v2.dart:22-35`) | none (mobile has the false copy, 0.4) | `lib/utils/account_delete_copy.dart` as `accountDeleteMessage`, `accountDeleteError` |
| private contrast check `account_setup_view.dart:860` | duplicate of `accountBadgeForeground` (`lib/utils/account_badge.dart:220`) | use `accountBadgeForeground` |

Also in this phase:
- Delete the dead files `lib/views/treasury/dashboard/cash_summary_banner.dart` and `account_card_widget.dart` (nothing imports them).
- Remove the unreachable `'Owed:'` branch in `dashboard_accounts_list.dart:142`.

Tests: existing web setup tests stay green; a unit test pins each account-type label once.

*Built note:* the label copy uses the web casing ("Time Deposit", "Credit Card"), so the mobile dashboard subtitle changes from "Time deposit". Web v1 files (`web_dashboard_page.dart`, `web_account_form_dialog.dart`) keep their own copies; they go with the Plan 063 v1 cleanup.

### Phase 2 — One budget status for both apps · `feat/budget-status-shared` · Effort S–M

Today:
- Web v2 has `_statusFor` in a view (`web_budget_page_v2.dart:107-122`). It gives On track / Watch · N% / Over by ₱X / Funded, and uses the warning tone (`appColors.bills`) for Over.
- Mobile has no Watch state. `budget_card.dart:35-48, 150-157` and the pace pill (`budget_view.dart:363`) use red (`cs.error`) only. `budget_overview_card.dart:77` hardcodes `0.75` and uses `gold`.

Do:
1. Add `BudgetStatus` and `budgetStatusFor(...)` to `budget_presenter.dart` (§4). It reads `kBudgetWatchThreshold`.
2. Add `status` and `statusLabel` to `BudgetSectionRow` and `WebBudgetRow`, filled in the presenter.
3. Mobile `budget_card.dart`: show the status label as text (not color only). Over and Watch use `appColors.bills`. Funded uses `appColors.treasury`.
4. Mobile pace pill: warning tone when over pace, same as web.
5. Mobile `budget_overview_card.dart` (Dashboard Budget Health): read the presenter status, show a text badge, hide groups with nothing allocated and nothing spent, add an "Open budget" link that switches to the Budget tab.
6. Web v2 `web_budget_page_v2.dart` and `web_dashboard_page_v2.dart:1201-1210` drop their private status code and read the presenter.
7. Group header on mobile adds "N% used" / "Funded" next to the existing subtotal.

Tests: `budgetStatusFor` table test (0, 0.74, 0.75, 1.0, over, savings funded); widget test that an over row shows "Over by ₱X" text.

### Phase 3 — Category and slice colors · `fix/treasury-slice-colors` · Effort S–M

- `category_pie_chart_card.dart:172, 238` call `resolveSliceColor` without `brightness`. Pass `Theme.of(context).brightness`.
- Replace private hex parsing with `resolveSliceColor` / `categoryColorAt` in: `transaction_list_tile.dart:47-53`, `manage_categories_sheet.dart:379, 483`, `account_badge_widget.dart:53, 286`, `account_setup_view.dart:795`, `goal_progress_card.dart:29`.
- History unknown-category fallback: use the palette by position, as web does (`web_month_detail_dialog_v2.dart:164`), not `onSurfaceVariant`.

Tests: golden-free widget test that a light-theme slice color differs from the dark one for the same hex.

### Phase 4 — Ledger ports · `feat/mobile-ledger-v2` · Effort M

1. **Notes under the description.** `transaction_list_tile.dart:103-129` adds one muted, 1-line, ellipsized note line when the note is not empty.
2. **Row actions.** The long-press sheet (`transaction_list_tile.dart:136-160`) gets the web v2 menu items, with the same visibility rules as `web_ledger_page_v2.dart:1505-1510`:
   - Edit
   - Duplicate (opens the sheet prefilled, date = today)
   - Split into installments (expense on a credit account only)
   - I'll get this back (expense, not already reimbursable)
   - Delete (group delete + Undo, as in 0.1)
3. `AddTransactionSheet` gets `duplicateOf`, `initialSplit` and `initialReimbursable` (§4). Model the prefill on `_initFromDuplicate` (`web_transaction_dialog_v2.dart:246-265`).
4. **Transfer legs in one place.** Add `LedgerPresenter.transferLegsOf(record)`. Mobile (`add_transaction_sheet.dart:116-121`) and web (`web_transaction_dialog_v2.dart:267-275`) both call it.
5. **"More options" fold.** New `AppFold` in `lib/views/widgets/system/foundation/app_fold.dart` (§4). In `AddTransactionSheet`, put Note and the reimbursable card under "More options". It opens on its own when either has a value. Installments get their own fold. Goal: Save stays above the keyboard fold on a 360×640 dp screen.
6. **Removable filter chips.** Under the controls row, a sideways-scrolling row of chips, 1 per active filter, each with ✕. Chips come from a presenter getter `activeFilterChips`.
7. **Correct empty text.** When filters hide everything: "No transactions match these filters" + "Clear filters". Otherwise: "No transactions this month". Drop "Tap + to log" (there is no + button).
8. **Rule-1 cleanup** while in these files: move the account/category lookup in `_buildTxnTile` (`ledger_view.dart:1184-1192`) and `_DateGroup._dailyNet` (`:1288-1294`) into presenter getters.

Tests: Duplicate opens the sheet with the same amount, account and category and today's date; action visibility per record type; empty text switches with filters; notes line shows only when a note exists.

### Phase 5 — One Settle sheet · `feat/mobile-settle-sheet` · Effort L

Replace 6 sheets with 1:
- `_MarkBillPaidSheet`, `_MarkReceivedSheet`, `_MarkExpensePaidSheet`, `_MarkInstallmentPaidSheet` (all in `bills_receivables_view.dart`)
- `batch_settle_sheet.dart`
- `shared/quick_pay_sheet.dart`

Do:
1. Move `SettleKind`, `SettleTarget` and `SettleResult` out of `lib/views/web/widgets/web_settle_dialog.dart` into `lib/models/settle_request.dart`. Web imports them from there. No behavior change on web.
2. Move the settle checks web does in the dialog (short-balance warning `web_settle_dialog.dart:381-388`, card overpay block `:503-509`, amount checks) into pure functions in `lib/utils/settle_rules.dart`. Web and mobile both call them.
3. New `lib/views/treasury/shared/settle_sheet.dart`: `showSettleSheet(...)` (§4). Single mode (editable amount) and batch mode (list of rows, one shared account and date). "Already added to ledger" goes under "More options" (`AppFold`).
4. On a failed save: error toast, sheet stays open (keeps the 0.2 fix).
5. Port every call site. Each call site keeps its own presenter call (`markBillPaid`, `markReceivableReceived`, `quickPayCard`, batch methods). The sheet only collects input and returns `SettleResult`.
6. Delete the 4 private sheets, `batch_settle_sheet.dart` and `quick_pay_sheet.dart`. `bills_receivables_view.dart` loses about 640 lines.

Tests: one test per `SettleKind` in single mode; batch mode settles each target for its own amount; short balance shows the warning; card overpay is blocked; failed save keeps the sheet open.

### Phase 6 — Bills tab: each bill in one place · `feat/mobile-bills-v2` · Effort M–L

Today a due-soon bill shows 3 times: `DueSoonStack` (`due_soon_stack.dart:59`), Coming up (`bills_receivables_view.dart:1250`, `comingUpItems`), and the Bills section (`:887-895`, paid and unpaid mixed).

Do:
1. **Presenter getters first** in `BillsReceivablesPresenter` (§4): `heroBill`, `unpaidDueSoon`, `unpaidLater`, `paidBills`, `setAsidePendingTotal`, `setAsidePendingCount`, `tabCounts`. Web v2 (`web_bills_page_v2.dart:140-173`) switches to them in the same PR, which removes its own rule-1 break.
2. **Hero** shows only `heroBill` (the first due-soon unpaid bill). The other due-soon bills go in the "Due soon" group at the top of the Upcoming tab.
3. **Tabs with counts:** Upcoming · Set-asides · Receivables · Installments · Paid. Use a scrollable chip row (5 labels do not fit an `AppSegmentedControl` at 360 dp). Batch select works inside one tab, as today.
4. **Coming up:** see open question Q2.
5. **Credit cards card** under the list: owed, available, Pay → `showSettleSheet(kind: cardPayment)`. Uses `quickPayCard` and `totalCreditAvailable`.
6. **This month summary:** a collapsible card under the hero with pending, paid, receivables, set-asides and "By account" from `fundingBreakdown()`. It replaces `_StatChips` (`:1482-1513`).
7. **Split the file:** move `_Section`, `_StatChips` and the tab bodies out of `bills_receivables_view.dart` into `lib/views/treasury/bills/` files.
8. **Forms:** optional fields go under "More options" in `add_installment_sheet.dart` (Category, Deferred, Interest, Note), `add_budgeted_expense_sheet.dart:260-278` and `add_bill_sheet.dart:343`.

Tests: a bill appears exactly once besides the hero; each tab count equals the presenter list length; Paid tab holds only paid bills; batch select stays inside one tab.

### Phase 7 — Dashboard ports · `feat/mobile-dashboard-v2` · Effort M

1. **Outlook as a signed statement.** Replace the 2×3 tile grid (`metric_cards_grid.dart:50-107`) with a vertical list in the same style as the Next Month card (`next_month_forecast_card.dart:246-300`). Extract the shared line widget so both cards use it.
2. **Projected month-end cash once.** Today it shows 3 times (strip `cashflow_strip.dart:254`, grid `:98`, Next Month "Starts at"). Keep it in the outlook and in "Starts at". Remove it from the strip.
3. **Cash flow strip** uses the freed space for net flow, "Spent N% of income" and a savings-rate badge (`monthNetCashFlow`, `savingsRate`).
4. **One empty state** when there are no accounts: hide the hero, strip, outlook, forecast and spending cards. Show one `AppEmptyState` with "Add your first account" → Setup. The decision is a presenter getter (`hasAccounts`).
5. **Hero stats:** add net cash flow and total assets under the net worth figure, with `formatPesoCompact` so they fit at 360 dp (liquid cash already sits in the Accounts header).
6. **Credit card row** shows "Owe ₱X · ₱Y available" (`totalCreditAvailable`). Pay stays visible but disabled when nothing is owed.
7. **Accounts list:** the "Overdrawn · check the last transfer" sub-line and an "All N" link (`accountInventoryCount`).
8. **Touch targets (rule 4):** range selector segments in `spending_analytics_card.dart:150` (about 34 px today), and the "View Full" / "View All" links (`:68`, `category_pie_chart_card.dart:29`), go to at least 44×44.
9. **Copy:** sentence case to match web ("Set-asides due", not "Budget / Savings Due").
10. **Rule-1 cleanup** in the dashboard cards the scan listed (`spending_analytics_card.dart:33-64`, `budget_overview_card.dart:22, 85-89`, `cashflow_strip.dart:199-201`, `upcoming_bills_card.dart:27-28`, `category_pie_chart_card.dart:23`, `treasury_dashboard_view.dart:667`): move the math to presenter getters.

Tests: outlook renders the 6 presenter values in order with `−₱` for negatives; empty state shows with no accounts and hides the cards; projection text appears once on the strip-plus-outlook area.

### Phase 8 — History "Open in Ledger" · `feat/mobile-history-open-ledger` · Effort S

- `monthly_summary_detail_view.dart` gets an `onOpenInLedger` callback and an "Open in Ledger" button.
- `treasury_history_view.dart` passes a callback from `TreasuryModuleView` that calls `ledger.setMonth(month)` (or the shared `TreasuryMonthScope` if it owns the month), pops the detail screen, and animates `_tabController` to the Ledger tab.
- Same behavior as web (`treasury_web_app.dart:699-702`).

Test: tapping the button sets the ledger month and selects the Ledger tab.

### Phase 9 — Setup and Goals · `feat/mobile-setup-goals-v2` · Effort M

1. **Credit / target meter** on mobile account rows (`dashboard_accounts_list.dart`, setup list): available of limit for credit, % of target for goals. Read `availableCredit`, `utilization`, `goalProgress`. Add a "Needs a fix" flag for overdrawn liquid accounts.
2. **Archive** in the account edit form for goal accounts (the presenter method already exists for web; reuse it).
3. **Goals hero figures:** move web `_GoalsFigures` (`web_goals_page.dart:197-271`) into `TreasuryDashboardPresenter` getters. Web and mobile read them. Mobile `goals_savings_screen.dart` hero shows Active funded / Not started / Set-asides this month.
4. **"How goals are funded" note** with a link to the Savings rows in Budget (web `:808-880`).
5. **Start again** on active goals too, not only completed ones (web `:501-505`).
6. Replace `Colors.white` on the Goals button (`goals_savings_screen.dart:116`) with `colorScheme.onPrimary`. Move the `.where` filter at `:101-103` into the presenter.

Tests: meter shows only on credit and goal rows; goal hero figures equal the presenter getters; Archive shows only for goals.

### Phase 10 — Larger items · Effort L (each its own PR)

- **10a. Search across all months** · `feat/ledger-search`. Query state lives in `LedgerPresenter` (`searchQuery`, `searchAllMonths`, `searchResults`), not in the view. A search field in the ledger header, with a "This month / All months" scope. Web v2 moves its view-side matching (`web_ledger_page_v2.dart:213-257`) onto the same presenter state.
- **10b. Trends switch** · `feat/mobile-trends-switch`. The existing `spending_analytics_card.dart` gets a segmented switch: Spending · Net worth · Income vs expenses (`incomeExpenseTrend()`). No new cards.

### Follow-up (not this plan) — Web v1 cleanup

Plan 063 Phase 11 step 3 is still open: the old `web_*_page.dart` files and the dead kit (`web_quick_pay_dialog.dart`, `web_batch_settle_dialog.dart`, `web_tile_flow.dart`, `web_section.dart`) are still in the tree, and `kWebV2` still exists. That is web-only work and belongs to Plan 063. Do it before Phase 5 if possible, so Phase 5 does not have to keep old web callers compiling.

## 4. Interface definitions

```dart
// lib/utils/finance_format.dart  (Phase 0)
/// '₱1,234.00' for >= 0, '−₱1,234.00' (typographic minus) below zero.
String formatPesoMinus(double amount);

// lib/utils/account_form_rules.dart  (Phase 1) — moved from views/web
const List<String> kAccountColorOptions;
String? positiveAmountValidator(String? v);
String? optionalPositiveAmountValidator(String? v);   // credit limit, goal target

// lib/utils/account_category_label.dart  (Phase 1) — moved from views/web/design
extension AccountCategoryLabel on AccountCategory { String get label; }

// lib/utils/account_delete_copy.dart  (Phase 1)
String accountDeleteMessage(FinancialAccount account);
String accountDeleteError(StateError e);

// lib/presenters/budget_presenter.dart  (Phase 2)
enum BudgetStatus { onTrack, watch, over, funded }
({BudgetStatus status, String label}) budgetStatusFor({
  required double allocated,
  required double spent,
  required bool accountBacked,
});
// BudgetSectionRow and WebBudgetRow gain:
final BudgetStatus status;
final String statusLabel;   // 'On track' · 'Watch · 82%' · 'Over by ₱1,200' · 'Funded'

// lib/views/widgets/system/foundation/app_fold.dart  (Phase 4)
class AppFold extends StatefulWidget {
  const AppFold({required this.title, this.subtitle, this.initiallyOpen = false,
      required this.child});
}

// lib/views/treasury/ledger/add_transaction_sheet.dart  (Phase 4)
AddTransactionSheet({
  ...,                                   // existing params unchanged
  TransactionRecord? duplicateOf,
  bool initialSplit = false,
  bool initialReimbursable = false,
});

// lib/presenters/ledger_presenter.dart  (Phase 4, 10a)
({TransactionRecord? from, TransactionRecord? to}) transferLegsOf(TransactionRecord r);
List<LedgerFilterChip> get activeFilterChips;   // label + clear callback id
bool get filtersHideEverything;
String get searchQuery;            // 10a
bool get searchAllMonths;          // 10a
List<TransactionRecord> get searchResults;   // 10a
void setSearch(String query, {bool allMonths});

// lib/models/settle_request.dart  (Phase 5) — moved from web_settle_dialog.dart
enum SettleKind { bill, receivable, setAside, installment, cardPayment }
class SettleTarget { ... }   // unchanged
class SettleResult { ... }   // unchanged

// lib/utils/settle_rules.dart  (Phase 5)
String? settleAmountError({required double? amount, required SettleKind kind,
    required double scheduled, double? cardPayable});
bool settleShortBalance({required double amount, required FinancialAccount from});

// lib/views/treasury/shared/settle_sheet.dart  (Phase 5)
Future<SettleResult?> showSettleSheet(
  BuildContext context, {
  required SettleKind kind,
  required List<SettleTarget> targets,          // 1 = single, >1 = batch
  required List<FinancialAccount> payers,
  required Future<void> Function(SettleResult) onConfirm, // caller's presenter call
});

// lib/presenters/bills_receivables_presenter.dart  (Phase 6)
Bill? get heroBill;
List<Bill> get unpaidDueSoon;     // excludes heroBill
List<Bill> get unpaidLater;
List<Bill> get paidBills;
double get setAsidePendingTotal;
int get setAsidePendingCount;
({int upcoming, int setAsides, int receivables, int installments, int paid}) get tabCounts;

// lib/presenters/treasury_dashboard_presenter.dart  (Phase 7, 9)
bool get hasAccounts;
// Goals figures moved from web_goals_page.dart:
double get goalsActiveFunded;
int get goalsNotStartedCount;
double get goalSetAsidesThisMonth;
```

No new `StorageService` keys or methods.

## 5. Affected files (summary)

| File | Action | Layer | Phase |
|---|---|---|---|
| `lib/utils/finance_format.dart` | Modify | Utils | 0 |
| `lib/views/treasury/ledger/add_transaction_sheet.dart` | Modify | View | 0, 4 |
| `lib/views/treasury/bills/bills_receivables_view.dart` | Modify, then split | View | 0, 5, 6 |
| `lib/views/treasury/bills/batch_settle_sheet.dart` | Modify, then delete | View | 0, 5 |
| `lib/views/treasury/shared/quick_pay_sheet.dart` | Modify, then delete | View | 0, 5 |
| `lib/views/treasury/shared/account_setup_view.dart` | Modify | View | 0, 1, 3, 9 |
| `lib/views/treasury/dashboard/*` | Modify | View | 0, 2, 3, 7, 9 |
| `lib/views/treasury/dashboard/cash_summary_banner.dart`, `account_card_widget.dart` | Delete | View | 1 |
| `lib/utils/account_form_rules.dart`, `account_category_label.dart`, `account_delete_copy.dart` | Create (moved from web) | Utils | 1 |
| `lib/views/web/pages/setup/web_account_form_rules.dart`, `lib/views/web/design/account_category_label.dart` | Delete (moved) | View | 1 |
| `lib/presenters/budget_presenter.dart` | Modify | Presenter | 2 |
| `lib/views/treasury/budget/budget_card.dart`, `budget_view.dart` | Modify | View | 2 |
| `lib/views/web/pages/budget/web_budget_page_v2.dart`, `web_dashboard_page_v2.dart` | Modify (read presenter status) | View | 2, 7 |
| `lib/views/widgets/system/foundation/app_fold.dart` | Create | View | 4 |
| `lib/presenters/ledger_presenter.dart` | Modify | Presenter | 4, 10a |
| `lib/views/treasury/ledger/transaction_list_tile.dart`, `ledger_view.dart` | Modify | View | 3, 4, 10a |
| `lib/models/settle_request.dart` | Create (moved from web) | Model | 5 |
| `lib/utils/settle_rules.dart` | Create | Utils | 5 |
| `lib/views/treasury/shared/settle_sheet.dart` | Create | View | 5 |
| `lib/views/web/widgets/web_settle_dialog.dart` | Modify (imports, rules) | View | 5 |
| `lib/presenters/bills_receivables_presenter.dart` | Modify | Presenter | 6 |
| `lib/views/web/pages/bills/web_bills_page_v2.dart` | Modify (read presenter getters) | View | 6 |
| `lib/views/treasury/history/monthly_summary_detail_view.dart`, `treasury_history_view.dart`, `treasury_module_view.dart` | Modify | View | 8 |
| `lib/presenters/treasury_dashboard_presenter.dart` | Modify | Presenter | 0, 7, 9 |
| `lib/views/treasury/dashboard/goals_savings_screen.dart`, `lib/views/web/pages/goals/web_goals_page.dart` | Modify | View | 9 |
| `test/...` | Create/Modify per phase | Test | all |

## 6. RPG impact

None intended. Treasury has no XP, level or streak math in these paths. No new notifications. Phase 0.1 changes which delete method the edit sheet calls; `deleteTransactionOrGroup` already runs the same balance reversal as swipe-delete, so no stat side effects change.

## 7. Risks and edge cases

| Risk | Mitigation |
|---|---|
| 0.1: group delete on an installment purchase must still take its plan with it. | `deleteTransactionOrGroup` calls `deleteTransaction` for non-transfers, which already handles plans. Test both a transfer and an installment purchase. |
| 0.1: Undo after the sheet closes needs a context that still exists. | Capture the ledger's `ScaffoldMessenger`/toast host before `pop`, as swipe-delete does. |
| Moving web files in Phase 1 and 5 breaks the old v1 web pages that still import them. | Do the Plan 063 v1 cleanup first, or leave a 1-line re-export in the old path until it lands. |
| Phase 5 changes a presenter call by accident. | The sheet only returns `SettleResult`; each call site keeps its own presenter call. One test per kind. |
| Phase 6 tabs: a bill can be due soon and in a batch selection at the same time. | Batch select stays inside one tab; switching tabs clears the selection (same as section locking today, `bills_receivables_view.dart:88-92`). |
| Phase 6 removes the Coming up duplicate, but the Hub card reads `comingUpItems`. | Do not change `comingUpItems`. Only the Bills tab view stops rendering it (or filters bills out in a new getter). Rule 8 holds. |
| Phase 7 hero stats truncate on small phones. | `formatPesoCompact`, 2 cells, test at 360 dp width. |
| Budget totals differ: mobile Dashboard uses expense-only totals, web uses totals with savings. | Open question Q1. Do not change either until the owner picks one. |
| `AppFold` hides a field that has an error. | The fold opens on its own when a field inside it has a value or an error. |
| Light mode regressions. | Each phase's widget tests run in both themes. |

## 8. Acceptance criteria

- [ ] Deleting a transfer from the mobile edit sheet removes both legs, and Undo restores both. Balances match before and after.
- [ ] Every mobile pay/settle path shows an error and stays open when the save fails.
- [ ] No mobile screen shows `₱-` for a negative amount.
- [ ] The mobile account delete copy matches what the presenter allows. Credit Limit rejects bad input.
- [ ] One copy each of: account form rules, account-type labels, delete copy, settle types, settle rules, budget status. No copy under `lib/views/web/` that mobile duplicates.
- [ ] Budget rows on both apps show the same status text for the same data, from `kBudgetWatchThreshold`. Over is not red-only.
- [ ] Category colors respect light mode on every Treasury surface.
- [ ] Ledger: notes visible in the list; Duplicate, Split, I'll get this back and Delete in the row menu; filter chips removable one by one; correct empty text.
- [ ] One mobile Settle sheet. The 4 private sheets, `batch_settle_sheet.dart` and `quick_pay_sheet.dart` are gone.
- [ ] On the Bills tab, a bill appears once besides the hero. Tabs show correct counts.
- [ ] Dashboard: outlook as a statement, projection shown once, one empty state with no accounts, touch targets ≥ 44×44.
- [ ] History month detail opens the Ledger at that month.
- [ ] `flutter analyze` clean, `flutter test` green, `dart format` applied, in every PR.

## 9. Out of scope (checked and rejected for mobile)

- Ledger footer month totals: mobile removed them on purpose; totals live on the Dashboard. (Could return later as a filtered total only.)
- Scan receipt in the header: the mobile bottom bar is better for the thumb (rule 4).
- Accounts table, inline cell editing, draft row, column resize, bulk selection bar on the ledger: desktop-only.
- Add ▾ menu and Bills batch select: mobile already has both (`NewEntrySheet`, `BatchActionBar`).
- Donut beside the budget ring: low value on a narrow screen.
- Hub cards: not touched, except through presenter getters they already read.

## 10. Open questions for the owner

- **Q1. Budget totals on the Dashboard:** expense-only (mobile today) or including savings groups (web today)? Recommendation: **expense-only.** "Budget health" asks "am I overspending?", and money moved into a goal is not spending. Web v2 should switch to the expense-only getters.
- **Q2. Coming up on the Bills tab:** drop bills from it, or drop the whole Coming up section from the Bills tab? Recommendation: **drop the section from the Bills tab.** The Upcoming tab already shows the same bills in date order. Keep Coming up on the Dashboard and Hub.
- **Q3. Edit-sheet Delete:** keep the confirm dialog and add Undo, or Undo only (like swipe and web)? Recommendation: **Undo only.** One delete behavior everywhere, and Undo is a better safety net than a confirm people tap through. **Phase 0 used the recommendation (Undo only).** Revert to a confirm if the owner prefers it.
