# Treasury web — parity checklist (Plan 063)

> Status: ACCEPTANCE LIST · Authored: 2026-10-10 (Phase 0) · Plan: `.claude/plans/063-treasury-web-v2-migration.md`
> Scope: every user-facing action on the **current** Treasury web UI (`lib/views/web/`), read off the page and widget source on `feat/web-v2` at Phase 0. The Cart page is excluded (removed from the desktop web by the owner; it stays in the narrow < 840 dp layout).

## How to use this list

- One line per action: `- [ ] <Page> · <action> · <where it is today>`. The third column names the widget or section that provides the action **today**, so a later phase can find it; it is not a requirement that the v2 page keep the same widget.
- Each later phase (3–10) ticks the lines of the page it migrates. A line that cannot be ticked needs either a `WebKeys` parity test proving the action exists on the v2 page, or an explicit "dropped" note signed off by the owner (§3 of the plan already lists the sanctioned drops: Cart destination, duplicate topbar title, the 4-tile Budget strip, the "—" in empty credit cells, the Bills triple-listing, the Ledger column washes).
- Lines under **Shared kit** are checked once, by the phase that rebuilds that widget (Phase 2 for the kit, Phase 5 for Settle, Phase 4 for the dropdown).
- Read-only states (empty / loading / error) are listed too — a page that loses its empty state loses a feature.
- Phase 11 walks the whole list on `localhost:8090` with `--dart-define=PREVIEW_SEED=true --dart-define=WEB_V2=true` at 1280, 1440 and 1920 px, Nudgy open and closed, dark and light.

Things that are **not** in the current web and therefore not on this list (checked while writing it, so a v2 reviewer does not go looking for them): no app-level keyboard shortcuts (only Enter-to-submit in fields, Esc in the searchable dropdown and the default dialog Esc); no running-balance column in the Ledger (only "Acct. Balance" after each row); no row Duplicate action; no "Open in Ledger" in the History month detail; no parent picker in the account form (the parent comes from the row's ⊕); no reorder in Manage groups; no legend toggles on any chart; no hover tooltip on the donuts or the hero sparkline; no Undo on any Budget or Setup toast; no paste-to-attach for receipts; no bell on Bill rows (the reminder lives in the Add/Edit Bill dialog).

---

## Shell

- [ ] Shell · Boot spinner shown while the app starts and restores the session · `TreasuryWebShell` build, full-screen `CircularProgressIndicator`
- [ ] Shell · Signed-out user sees the login screen instead of the app · `TreasuryWebShell` ListenableBuilder on auth, swaps in `WebLoginView`
- [ ] Shell · Dev preview-seed mode opens the dashboard without signing in · `TreasuryWebShell` initState, `previewSeedEnabled` path
- [ ] Shell · Signing in starts sync: pull from cloud, then push in the background · `_initSync` via `AuthPresenter.onFirstSignIn`
- [ ] Shell · "Sync failed" toast with a Retry button (8s, error colour) · `_initSync` catch block, `AppToast.action`
- [ ] Shell · Refocusing the browser tab pulls then pushes changes (30s staleness) · `didChangeAppLifecycleState` resumed, `syncCycle`
- [ ] Shell · Edits from another device appear within seconds (realtime) · `RealtimeSyncService` set up in `_initSync`
- [ ] Shell · Daily cloud snapshot backup is written silently on sign-in · `SnapshotService.writeSnapshotIfDue` in `_initSync`
- [ ] Shell · Sign-out flushes pending changes and keeps local data · `_tearDownSync` (non-destructive detach)
- [ ] Shell · Layout switches to the desktop sidebar at the rail breakpoint or wider · `_TreasuryWebHome` LayoutBuilder, `WebBreakpoints.rail`
- [ ] Shell · Narrow layout uses mobile bottom tabs plus an extra "More" tab · `_TreasuryWebHome` narrow branch, `TreasuryModuleView` + `extraTabs`
- [ ] Shell · Current page is kept when the window crosses the breakpoint · `_index` shared via `initialTabIndex` / `onTabChanged`
- [ ] Shell · Narrow layout passes sync status to the mobile module · `TreasuryModuleView(syncPresenter:)`
- [ ] Shell · Sidebar brand header: wallet icon and "Treasury" title (not clickable) · `WebShell.header` Row
- [ ] Shell · Go to Dashboard · Sidebar `_RailItem` "Dashboard"
- [ ] Shell · Go to Ledger · Sidebar `_RailItem` "Ledger"
- [ ] Shell · Go to Bills · Sidebar `_RailItem` "Bills"
- [ ] Shell · Go to Budget · Sidebar `_RailItem` "Budget"
- [ ] Shell · Go to History · Sidebar `_RailItem` "History"
- [ ] Shell · Go to Cart — DROPPED on desktop by Plan 063; must still exist in the narrow (< 840 dp) tabs · Sidebar `_RailItem` "Cart"
- [ ] Shell · Go to Goals (Goals & Savings screen, no app bar) · Sidebar `_RailItem` "Goals"
- [ ] Shell · Go to Setup & Accounts · Sidebar `_RailItem` "Setup & Accounts"
- [ ] Shell · Selecting a page reloads its data · `_onSelect` → `_reloadFor`
- [ ] Shell · Selected page is highlighted with primary tint and bolder label · `_RailItem` selected style
- [ ] Shell · Hovering a nav item shows a hover background and pointer cursor · `_RailItem` MouseRegion
- [ ] Shell · Ledger filters survive leaving and returning to Ledger · `_TreasuryWebHomeState._ledgerFilters`
- [ ] Shell · Sidebar nav list scrolls when it overflows · `WebShell` SingleChildScrollView
- [ ] Shell · Topbar shows the current page name — DROPPED by Plan 063 (duplicate of the page header); the page header must carry the name instead · Topbar left, `Text(_destinations[_index].label)`
- [ ] Shell · Toggle light/dark theme · Topbar right, `_ThemeToggle` IconButton
- [ ] Shell · Theme toggle tooltip reads "Switch to light/dark mode" · `_ThemeToggle` tooltip
- [ ] Shell · Theme toggle icon changes (sun in dark, moon in light) · `_ThemeToggle` icon
- [ ] Shell · App opens in dark theme by default · `webThemeMode` initial `ThemeMode.dark`
- [ ] Shell · Sync status line: synced, pending upload, or "Sync failed" · Sidebar footer, `_SignOutFooter` sync row
- [ ] Shell · Sync status hidden while sync is not running or failed to start · `_SignOutFooter` `if (sync != null)`
- [ ] Shell · Signed-in email shown (cut off with ellipsis if long) · Sidebar footer, `_SignOutFooter` email Text
- [ ] Shell · Sign out · Sidebar footer, `OutlinedButton.icon` "Sign out"
- [ ] Shell · "Ask Nudgy" launcher reachable on every page (floats bottom-right today; header button in v2) · `WebShell.dockLauncher` Positioned over body
- [ ] Shell · Nudgy panel docks to the right of every page and takes its own width · `WebShell.dock` (`NudgyPanel`)

## Login

- [ ] Login · App logo, "Treasury" title and tagline shown · `WebLoginView` header column
- [ ] Login · Sign in with Google (full-page OAuth redirect) · `AppPrimaryButton` "Continue with Google"
- [ ] Login · Button shows loading and is disabled while signing in · `AppPrimaryButton` `isLoading`
- [ ] Login · Sign-in error appears as an error toast, then clears · `AppToast.error` + `presenter.clearError()` post-frame
- [ ] Login · No guest or "log in later" option on web (keep it that way) · `WebLoginView` (absence; parity note)

## Nudgy

- [ ] Nudgy · Open Nudgy panel · Floating `FloatingActionButton.extended` "Ask Nudgy" (`NudgyLauncher`)
- [ ] Nudgy · Launcher tooltip "Log a transaction or ask about your money" · `NudgyLauncher` tooltip
- [ ] Nudgy · Launcher shrinks away while the panel is open · `NudgyLauncher` AnimatedScale
- [ ] Nudgy · Chat session starts only on first open · `NudgyController.open`
- [ ] Nudgy · Panel slides open and closed with a width animation · `NudgyPanel` AnimatedContainer 200ms
- [ ] Nudgy · Collapse Nudgy panel · Panel header right, IconButton chevron "Collapse Nudgy"
- [ ] Nudgy · Drag the left edge to resize the panel · `_ResizeHandle` horizontal drag strip (10px)
- [ ] Nudgy · Resize cursor and grip bar appear on hover or drag · `_ResizeHandle` MouseRegion + AnimatedContainer
- [ ] Nudgy · Double-click the edge to reset to default width · `_ResizeHandle` Listener → `resetWidth()`
- [ ] Nudgy · Width limited to 320–900px and always leaves 480px for the page · `NudgyController.applyResizeDelta` / `NudgyPanel` maxNow
- [ ] Nudgy · Dragged width is remembered between sessions · `NudgyController.endResize` → `saveNudgyPanelWidth`
- [ ] Nudgy · Panel title "Nudgy" with AI badge · Panel header Text + `_SheetHeader` "AI" chip
- [ ] Nudgy · Open saved conversations list · Chat header, IconButton "Conversations"
- [ ] Nudgy · Start a new chat · Conversations sheet, TextButton "New chat"
- [ ] Nudgy · Reopen a past conversation · Conversations sheet, `_ConversationTile` InkWell
- [ ] Nudgy · Delete a saved conversation · Conversations sheet, IconButton "Delete"
- [ ] Nudgy · Conversations empty state "No saved conversations yet." · `_ConversationsSheet`
- [ ] Nudgy · Current or archived conversation marked in the list · `_ConversationTile` isCurrent tint / archive icon
- [ ] Nudgy · Open advisor memory · Chat header, IconButton "Advisor memory"
- [ ] Nudgy · Add a goal to memory (Enter or + button) · Memory sheet, `_AddField` goals + IconButton "Add"
- [ ] Nudgy · Remove a remembered goal · Memory sheet, `_RemovableRow` IconButton "Remove"
- [ ] Nudgy · Set risk tolerance (saves on Enter or click outside) · Memory sheet, `_RiskToleranceField`
- [ ] Nudgy · Add a note to memory (Enter or + button) · Memory sheet, `_AddField` notes
- [ ] Nudgy · Remove a remembered note · Memory sheet, `_RemovableRow` IconButton "Remove"
- [ ] Nudgy · Clear all memory · Memory sheet, TextButton "Clear all memory" (shown only when memory is not empty)
- [ ] Nudgy · Clear conversation history and close the sheet · Memory sheet, TextButton "Clear conversation history"
- [ ] Nudgy · Switch between Think and Fast modes · Chat header, Think/Fast pill (GestureDetector)
- [ ] Nudgy · Think/Fast toggle disabled while a reply is coming in · `_SheetHeader` `isResponding ? null`
- [ ] Nudgy · Type a message or transaction · Input bar TextField (1–4 lines)
- [ ] Nudgy · Enter sends; Shift+Enter adds a new line · `_InputBar._sendOnEnter` Focus onKeyEvent
- [ ] Nudgy · Send message · Input bar `_SendButton`
- [ ] Nudgy · Input hint text explains why input is disabled · `_InputBar` hint from `presenter.inputHint`
- [ ] Nudgy · Attach a photo (bill, receipt, statement) · Input bar `_AttachButton`, advisor mode only
- [ ] Nudgy · Choose camera or gallery for the photo · `_PhotoSourceSheet` "Take photo" / "Choose from gallery"
- [ ] Nudgy · Remove the attached photo before sending · `_StagedImagePreview` close (x) GestureDetector
- [ ] Nudgy · Edit an earlier question and ask again · User bubble, IconButton "Edit and ask again"
- [ ] Nudgy · Edit-question dialog: change text, Cancel, or "Ask again" · `_EditQuestionDialog`
- [ ] Nudgy · Edit dialog warns how many messages below will be replaced · `_EditQuestionDialog` droppedBelow text
- [ ] Nudgy · Select and copy reply text · `_MessageList` SelectionArea
- [ ] Nudgy · Jump to newest message · Floating round button "Jump to newest" (shown when scrolled up)
- [ ] Nudgy · List auto-scrolls to new messages unless you scrolled up · `_AiChatBodyState` follow-tail logic
- [ ] Nudgy · Rotating "Thinking…" text while waiting for a reply · `_ThinkingLabel` in streaming bubble
- [ ] Nudgy · Status strip shows what Nudgy is doing (spinner + label) · `_StatusStrip`
- [ ] Nudgy · Error chip with Retry button (only when retry can work) · `_ErrorChip` TextButton "Retry"
- [ ] Nudgy · Dismiss error chip · `_ErrorChip` close (x) GestureDetector
- [ ] Nudgy · Empty conversation prompt "Ask me anything." · `_MessageList` empty state
- [ ] Nudgy · "Loading AI Coach…" while starting up · `_chatArea` isInitializing
- [ ] Nudgy · "Nudgy is unavailable" message when the cloud AI cannot be reached · `_CloudUnavailable` (no download offered on web)
- [ ] Nudgy · Confirm card: "Log it" / "Log all N" commits the entries · `AdvisorLogCard` → `EntryReviewCard` / `_Resolved` FilledButton
- [ ] Nudgy · Confirm card: Cancel the pending entry · `AdvisorLogCard` TextButton "Cancel"
- [ ] Nudgy · Log button disabled until every missing field is filled · `EntryReviewCard` `ready ? confirmEntries : null`
- [ ] Nudgy · Status line "Tap the lit chip…" / "Ready to log" · `EntryReviewCard._StatusLine`
- [ ] Nudgy · Edit an entry's amount (Amount dialog: Cancel / Set) · `_ReviewRow` amount `_TapTarget` → `_AmountDialog`
- [ ] Nudgy · Pick an entry's account · `_ReviewRow` account `_FieldChip` → picker sheet
- [ ] Nudgy · Pick a transfer destination account · `_ReviewRow` "Add destination" chip → picker sheet
- [ ] Nudgy · Pick an entry's category · `_ReviewRow` category chip → picker sheet
- [ ] Nudgy · Pick an entry's date (last 3 years up to today) · `_ReviewRow` date chip → `showDatePicker`
- [ ] Nudgy · Remove one entry from a multi-entry card · `_ReviewRow` IconButton "Remove this entry"
- [ ] Nudgy · "Check this" marker on low-confidence entries · `_ReviewRow` `_FieldChip` (not clickable)
- [ ] Nudgy · Clarify question with quick-reply chips · `AdvisorLogCard._Clarify` ActionChip
- [ ] Nudgy · Cancel a clarify question · `_Clarify` TextButton "Cancel"
- [ ] Nudgy · "Preparing your entry…" while parsing · `AdvisorLogCard._Thinking`
- [ ] Nudgy · Dismiss a logging error · `AdvisorLogCard._Error` IconButton "Dismiss"
- [ ] Nudgy · "✓ Logged …" note posted in chat after a commit · `_onLedgerSideEffects` appendAssistantNote
- [ ] Nudgy · Note when some entries still need the form opened · `_onLedgerSideEffects` pendingFormPrefill note
- [ ] Nudgy · Proposed change card: accept (or delete, for destructive actions) · `FinanceProposalCard` FilledButton (confirmLabel / "Add it")
- [ ] Nudgy · Proposed change card: "Not now" · `FinanceProposalCard` TextButton
- [ ] Nudgy · Recurring proposal: choose "This month" or "Every month ahead" · `FinanceProposalCard._ScopeChoice`

## Dashboard

- [ ] Dashboard · Loading spinner while data loads · `WebDashboardPage` isLoading
- [ ] Dashboard · "No accounts yet" empty state when there are no accounts · `_EmptyState`
- [ ] Dashboard · "Add your first account" goes to Setup & Accounts · `_EmptyState` FilledButton.icon
- [ ] Dashboard · Net worth hero: total, month % pill, "±₱X this month" · `WebNetWorthHero` `_Figure` / `_TrendPill` / `_ThisMonthLine`
- [ ] Dashboard · Hero says "Tracking this month" when there is no prior month · `_ThisMonthLine` delta == null
- [ ] Dashboard · Hero sparkline sits beside the figure (below it when narrow; hidden with no trend) · `WebNetWorthHero` LayoutBuilder
- [ ] Dashboard · Position tiles: Net Cash Flow, Liquid Cash, Total Assets · `_PositionRow` WebStatTile ×3
- [ ] Dashboard · Month-End Outlook chain: Liquid Now through Proj. Month-End Cash (6 figures) · `_MonthEndOutlookRow` WebStatTile ×6
- [ ] Dashboard · Projected month-end cash turns red when negative · `_MonthEndOutlookRow` valueColor
- [ ] Dashboard · Account balance tiles for liquid and credit accounts · `_AccountBalancesRow` tiles
- [ ] Dashboard · Account tile shows "held" amount or "Available credit" · `_AccountBalancesRow._tile` sub text
- [ ] Dashboard · Liquid cash total in the Accounts header · `_AccountBalancesRow` header Text
- [ ] Dashboard · Open the "All N" account list dialog · Accounts header right, TextButton "All N"
- [ ] Dashboard · Net Worth Trend line chart with change badge · `_NetWorthTrendCard` WebLineChart + WebBadge
- [ ] Dashboard · Hover a point on Net Worth Trend to see month and value · `WebLineChart` LineTouchData tooltip
- [ ] Dashboard · Net Worth Trend empty state (fewer than 2 months) · `_NetWorthTrendCard` `_CardEmpty`
- [ ] Dashboard · Cash Flow card: income, expenses, net, savings rate, flow bars · `_CashFlowCard`
- [ ] Dashboard · Income vs Expenses bar chart with legend · `_IncomeExpensesCard` WebBarPairChart
- [ ] Dashboard · Hover a bar to see series and value · `WebBarPairChart` BarTouchData tooltip
- [ ] Dashboard · Income vs Expenses empty state · `_IncomeExpensesCard` `_CardEmpty`
- [ ] Dashboard · Budget Health rows with On track / Watch / Over badges and total · `_BudgetHealthCard` WebBudgetRow
- [ ] Dashboard · Budget Health empty state "No budget set for this month yet" · `_BudgetHealthCard` `_CardEmpty`
- [ ] Dashboard · Daily Spending 7-day line chart · `_DailySpendingCard` WebLineChart
- [ ] Dashboard · Hover a day on Daily Spending to see the amount · `WebLineChart` tooltip
- [ ] Dashboard · Daily Spending empty state · `_DailySpendingCard` `_CardEmpty`
- [ ] Dashboard · Credit card: owed, utilisation bar, available of limit · `_CreditCard` / `_CreditAccountRow` (only when credit accounts exist)
- [ ] Dashboard · Credit due line (red when due soon) · `_CreditAccountRow` dueInfo row
- [ ] Dashboard · Statement cycle note or "no billing cycle" warning · `_CreditAccountRow` cycleNote row
- [ ] Dashboard · Pay a credit card · `_CreditAccountRow` FilledButton.tonalIcon "Pay Now"
- [ ] Dashboard · Pay Now disabled when nothing is owed · `_CreditAccountRow` `currentPayable > 0`
- [ ] Dashboard · Error toast "No account to pay from." · `_payNow` AppToast.error
- [ ] Dashboard · Pay dialog: amount field, pre-filled with amount owed · `_WebQuickPayDialog` (shared `web_quick_pay_dialog.dart`) TextFormField "Amount"
- [ ] Dashboard · Pay dialog: summary "You owe ₱X. This moves cash…" · shared quick-pay summary Text
- [ ] Dashboard · Pay dialog: amount checks (empty, over owed, over balance; re-validates on account change) · `_WebQuickPayDialog` validator
- [ ] Dashboard · Pay dialog: choose the "Pay from" account showing balances · `_WebQuickPayDialog` DropdownButtonFormField
- [ ] Dashboard · Pay dialog: pick the payment date · `_WebQuickPayDialog` InkWell → `showDatePicker`
- [ ] Dashboard · Pay dialog: Cancel · `_WebQuickPayDialog` TextButton "Cancel"
- [ ] Dashboard · Pay dialog: Pay (spinner while saving; disabled with no payers) · `_WebQuickPayDialog` FilledButton "Pay"
- [ ] Dashboard · Pay dialog: "Could not pay" error snackbar, dialog stays open · `_WebQuickPayDialog._submit` catch
- [ ] Dashboard · Success toast "Paid ₱X to <card>." · `_payNow` AppToast.success
- [ ] Dashboard · Where Your Money Goes donut with ranked legend · `_WhereMoneyGoesCard` WebDonutChart (no hover)
- [ ] Dashboard · Where Your Money Goes empty state · `_WhereMoneyGoesCard` `_CardEmpty`
- [ ] Dashboard · Savings Goals: progress bars for targets, balances for plain savings · `_SavingsGoalsCard`
- [ ] Dashboard · Savings Goals empty state · `_SavingsGoalsCard` `_CardEmpty`
- [ ] Dashboard · Cards flow into two balanced columns, one when narrow · `_ContentColumns` / `_MasonryFlow` (920px)
- [ ] Dashboard · Tile grids go from 4 to 2 to 1 columns with width · `_PositionRow` / `_AccountBalancesRow` / `_MonthEndOutlookRow` LayoutBuilder
- [ ] Dashboard · Account list dialog: "N total · M shown as tiles" header · `WebAccountInventoryDialog._Header`
- [ ] Dashboard · Account list dialog: groups with count, total or "owed" amount · `WebAccountInventoryDialog._Group`
- [ ] Dashboard · Account list dialog: shows whether each group is on the dashboard · `_Group` surfacedIn row
- [ ] Dashboard · Account list dialog: rows with icon, name, category, balance · `WebAccountInventoryDialog._Row`
- [ ] Dashboard · Account list dialog: "No accounts yet." empty state · `WebAccountInventoryDialog` groups.isEmpty
- [ ] Dashboard · Account list dialog updates if a sync lands while open · `WebAccountInventoryDialog` ListenableBuilder
- [ ] Dashboard · Close account list dialog (X) · Dialog header, IconButton "Close"
- [ ] Dashboard · Close account list dialog (footer button) · Dialog footer, TextButton "Close"
- [ ] Dashboard · Close dialogs with Esc or a click outside · Default `showDialog` behaviour (account list, pay dialog)

## Ledger

### Page shell, loading and toasts
- [ ] Ledger · Page title "Ledger" header shown above toolbar · WebPageHeader
- [ ] Ledger · Full-page spinner while ledger data loads · _LoadingBlock (CircularProgressIndicator)
- [ ] Ledger · Assistant leftovers auto-open prefilled Add dialog, one after another · _drainToForm → _AddTransactionDialog(prefill)
- [ ] Ledger · Toast "N more from that message after this one" · _drainToForm, AppToast.show
- [ ] Ledger · Filters/sort/search survive leaving and returning to Ledger · WebLedgerFilters (owned by shell)

### Toolbar · Month stepper and scope
- [ ] Ledger · Go to previous month · _Toolbar, IconButton chevron_left (tooltip "Previous month")
- [ ] Ledger · Go to next month · _Toolbar, IconButton chevron_right (tooltip "Next month")
- [ ] Ledger · Month label shows selected month (e.g. "Oct 2026") · _Toolbar, Text
- [ ] Ledger · Month arrows disabled while search/date range spans all months · _Toolbar, IconButton onPressed null
- [ ] Ledger · Label switches to "All months" when search/date range active · _Toolbar, Text
- [ ] Ledger · Scope pill "N matches across all months" (singular "1 match") · _ScopeNote pill

### Toolbar · Search
- [ ] Ledger · Type in "Search…" box to filter rows · _SearchField, TextField
- [ ] Ledger · Search matches description, note, category and account name · _matches (text match)
- [ ] Ledger · Search by amount ("1000", "1,000", "₱1,000") · _matches (numeric match)
- [ ] Ledger · Search runs after ~220ms typing pause (debounced) · _onSearchChanged Timer
- [ ] Ledger · Search widens grid to all months, not just selected month · WebLedgerFilters.spansAllMonths

### Toolbar · Add transaction
- [ ] Ledger · Open Add Transaction dialog · _AddButton, FilledButton.icon "Add Transaction"

### Toolbar · Active filter chips
- [ ] Ledger · Chip per selected account, × removes that account · _ActiveChip, InkWell close icon
- [ ] Ledger · Chip per selected category, × removes that category · _ActiveChip, InkWell close icon
- [ ] Ledger · "Inflow only"/"Outflow only" chip, × resets type to All · _ActiveChip
- [ ] Ledger · Date-range chip ("Oct 1 → Oct 9" / "From …" / "Until …"), × clears both dates · _ActiveChip (history icon)
- [ ] Ledger · Sort chip (preset label or "Custom sort"), × resets to default sort · _ActiveChip (swap_vert icon)

### Filters & Sort popover
- [ ] Ledger · Open/close Filters & Sort popover · _FiltersAndSort, OutlinedButton.icon "Filters & Sort"
- [ ] Ledger · Badge shows count of active filters on the button · _FiltersAndSort, count pill
- [ ] Ledger · Button border highlights when any filter is active · _FiltersAndSort, OutlinedButton style
- [ ] Ledger · Click outside popover to close it (click still reaches grid) · _buildPanel, translucent GestureDetector barrier
- [ ] Ledger · Filters · Accounts multi-select: pick to toggle an account (✓ marks selected) · WebSearchableDropdown in _FilterRow "Accounts"
- [ ] Ledger · Filters · "All accounts" entry clears account filter · WebSearchableDropdown entry value null
- [ ] Ledger · Filters · Accounts hint shows "N selected — add another" · WebSearchableDropdown hintText
- [ ] Ledger · Filters · Categories multi-select: pick to toggle a category (✓ marks selected) · WebSearchableDropdown in _FilterRow "Categories"
- [ ] Ledger · Filters · "All categories" entry clears category filter · WebSearchableDropdown entry value null
- [ ] Ledger · Filters · Type segment All / Inflow / Outflow · _TypeSegmented (GestureDetector + pointer cursor)
- [ ] Ledger · Filters · Sort by: Default (date order) · _PanelDropdown DropdownButton
- [ ] Ledger · Filters · Sort by: Newest first · _PanelDropdown item
- [ ] Ledger · Filters · Sort by: Oldest first · _PanelDropdown item
- [ ] Ledger · Filters · Sort by: Highest outflow · _PanelDropdown item
- [ ] Ledger · Filters · Sort by: Highest inflow · _PanelDropdown item
- [ ] Ledger · Filters · Sort by: Largest amount · _PanelDropdown item
- [ ] Ledger · Filters · Pick "From" date via date picker · _DateButton → showDatePicker
- [ ] Ledger · Filters · Pick "Until" date via date picker · _DateButton → showDatePicker
- [ ] Ledger · Filters · Inverted range auto-corrected (end snaps to start or vice versa) · WebLedgerFilters.setFromDate/setToDate
- [ ] Ledger · Filters · Date range widens grid to all months · WebLedgerFilters.spansAllMonths
- [ ] Ledger · Filters · "Clear all" resets filters, sort and search · TextButton "Clear all" → _clearFilters
- [ ] Ledger · Filters · "Done" closes popover · FilledButton "Done"

### Grid header (sort, select-all, resize)
- [ ] Ledger · Select/deselect all visible rows · _GridHeader, _Check (custom checkbox)
- [ ] Ledger · Click Date header to sort; click again to reverse · _HeaderCell InkWell
- [ ] Ledger · Click Account header to sort; click again to reverse · _HeaderCell InkWell
- [ ] Ledger · Click Description header to sort; click again to reverse · _HeaderCell InkWell
- [ ] Ledger · Click Category header to sort; click again to reverse · _HeaderCell InkWell
- [ ] Ledger · Click Inflow header to sort; click again to reverse · _HeaderCell InkWell
- [ ] Ledger · Click Outflow header to sort; click again to reverse · _HeaderCell InkWell
- [ ] Ledger · Active sort column highlighted; chevron flips for descending · _HeaderCell chevron
- [ ] Ledger · Acct. Balance header is not sortable · _HeaderCell (sortKey null)
- [ ] Ledger · Drag column edge to resize Date (80–360px) · _HeaderCell resize handle, resizeColumn cursor
- [ ] Ledger · Drag column edge to resize Account (110–420px) · _HeaderCell resize handle
- [ ] Ledger · Drag column edge to resize Category (110–420px) · _HeaderCell resize handle
- [ ] Ledger · Drag column edge to resize Inflow (90–260px) · _HeaderCell resize handle
- [ ] Ledger · Drag column edge to resize Outflow (90–260px) · _HeaderCell resize handle
- [ ] Ledger · Drag column edge to resize Acct. Balance (100–300px) · _HeaderCell resize handle
- [ ] Ledger · Description column stretches to fill leftover width (min 200px) · LayoutBuilder descW
- [ ] Ledger · Grid scrolls horizontally when columns overflow (visible scrollbar) · Scrollbar + horizontal SingleChildScrollView
- [ ] Ledger · Header and draft row stay pinned; only rows scroll vertically · Scrollbar + ListView
- [ ] Ledger · Green Inflow / red Outflow column tints run full height — DROPPED by Plan 063 (column washes) · Positioned ColoredBox washes

### Draft add-row (top of grid)
- [ ] Ledger · Draft · Pick date via date picker (defaults to today) · _DraftRow, _DateCell InkWell
- [ ] Ledger · Draft · Pick account (searchable, "Account" placeholder) · _DraftRow, _AccountCell WebSearchableDropdown
- [ ] Ledger · Draft · Account shows "—" when no accounts exist · _DraftRow, _readCell
- [ ] Ledger · Draft · Type description ("Add a row…") · _DraftRow, _InlineText
- [ ] Ledger · Draft · Pick category (list follows inflow vs outflow) · _DraftRow, _CategoryCell WebSearchableDropdown
- [ ] Ledger · Draft · Category shows "—" when none exist for that direction · _DraftRow, _readCell
- [ ] Ledger · Draft · Enter inflow amount (clears outflow) · _DraftRow, _AmountCell
- [ ] Ledger · Draft · Enter outflow amount (clears inflow) · _DraftRow, _AmountCell
- [ ] Ledger · Draft · Press Enter in description/amount to add row · _InlineText/_AmountCell onSubmitted → _commitDraft
- [ ] Ledger · Draft · Click ✓ "Add row" button to add · _DraftRow, IconButton check (tooltip "Add row")
- [ ] Ledger · Draft · No amount → add silently ignored · _commitDraft guard
- [ ] Ledger · Draft · No account picked → posts to first account · _commitDraft fallback
- [ ] Ledger · Draft · Error toast "Pick a category before adding the row." · _commitDraft, AppToast.error
- [ ] Ledger · Draft · Blank description defaults to category name or "Transaction" · _commitDraft
- [ ] Ledger · Draft · Row resets after a successful add · _commitDraft (_draftEpoch++)

### Existing rows · inline edit
- [ ] Ledger · Row · Toggle row selection checkbox · _EditableRow, _Check
- [ ] Ledger · Row · Selected row tinted; hovered row tinted · _EditableRow background
- [ ] Ledger · Row · Click date to change via date picker · _DateCell InkWell → showDatePicker
- [ ] Ledger · Row · Change account via searchable dropdown · _AccountCell WebSearchableDropdown
- [ ] Ledger · Row · Edit description inline (saves on blur or Enter) · _InlineText TextField
- [ ] Ledger · Row · Esc in description reverts and leaves the field · _InlineText Focus onKeyEvent
- [ ] Ledger · Row · Change category via searchable dropdown (with color dot) · _CategoryCell WebSearchableDropdown
- [ ] Ledger · Row · Edit inflow amount inline (switches row to inflow) · _AmountCell
- [ ] Ledger · Row · Edit outflow amount inline (switches row to outflow) · _AmountCell
- [ ] Ledger · Row · Switching inflow/outflow clears the category · _editAmount
- [ ] Ledger · Row · Focused amount shows raw number, all text selected · _AmountCell _onFocus
- [ ] Ledger · Row · Amount displays as ₱1,000.00; blank when zero · _AmountCell _display
- [ ] Ledger · Row · Clearing amount or entering 0 reverts to previous value · _AmountCell / _editAmount guard
- [ ] Ledger · Row · Esc in amount reverts and leaves the field · _AmountCell Focus onKeyEvent
- [ ] Ledger · Row · Amount field accepts only digits, "." and "," · _AmountCell inputFormatters
- [ ] Ledger · Row · Focus ring on active inline text/amount cell · _InlineText/_AmountCell decoration
- [ ] Ledger · Row · Error toast when edit would break an installment purchase · _commitInline, AppToast.error
- [ ] Ledger · Row · Acct. Balance column shows account balance after this row (read-only) · _EditableRow, _readCell
- [ ] Ledger · Row · Notes are stored but not shown in the grid today (v2 shows them under the description; must not lose the data) · TransactionRecord.note (Add dialog only)

### Transfer rows
- [ ] Ledger · Transfer · Category cell shows "Transfer" badge · _EditableRow, WebBadge (swap_horiz)
- [ ] Ledger · Transfer · Account cell shows only this leg's account (with dot) · _TransferAccountCell
- [ ] Ledger · Transfer · Date/desc/amount cells read-only · _EditableRow enabled:false
- [ ] Ledger · Transfer · Click row to open Edit dialog (hover tooltip "Edit transfer") · GestureDetector + Tooltip, click cursor

### Row hover actions, delete and undo
- [ ] Ledger · Hover row to reveal delete (trash) button (v2: row ⋯ menu, always visible) · _EditableRow, AnimatedOpacity IconButton (tooltip "Delete")
- [ ] Ledger · Delete a single row immediately, no confirm · IconButton → _deleteRow
- [ ] Ledger · Deleting a transfer leg deletes the whole transfer · _deleteRow → deleteTransactionOrGroup
- [ ] Ledger · Snackbar "Deleted "…"" / "Deleted transfer "…"" with Undo (6s) · _offerUndo SnackBar + SnackBarAction
- [ ] Ledger · Undo restores deleted rows · SnackBarAction "Undo" → restoreTransactions

### Selection bar and bulk delete
- [ ] Ledger · Selection bar shows "N selected" when rows selected · _SelectionBar
- [ ] Ledger · Clear selection · _SelectionBar, TextButton "Clear"
- [ ] Ledger · Bulk delete ("Delete" / "Delete N") · _SelectionBar, FilledButton.icon
- [ ] Ledger · Confirm dialog "Delete transactions?" · _confirmDelete AlertDialog
- [ ] Ledger · Confirm dialog · Cancel · TextButton "Cancel"
- [ ] Ledger · Confirm dialog · Delete (red) · FilledButton "Delete"
- [ ] Ledger · Snackbar "Deleted N transactions" with Undo · _offerUndo

### Empty states and footer
- [ ] Ledger · Empty (filtered): "No transactions match your filters." · _EmptyGridHint
- [ ] Ledger · Empty (filtered): "Clear filters" button · _EmptyGridHint, TextButton.icon
- [ ] Ledger · Empty (no rows): "No transactions this month — add one in the row above." · _EmptyGridHint
- [ ] Ledger · Empty (no accounts): "Add an account in Setup before logging transactions." · _EmptyGridHint
- [ ] Ledger · Footer hint: click cell to edit, Enter adds, drag edge resizes (v2: month totals replace the hint; the behaviours stay) · Table card footer Text

### Receipt scan
- [ ] Ledger · Receipt · Floating "Scan a receipt" button opens dialog (v2: toolbar button) · FloatingActionButton.small (bottom-right, tooltip)
- [ ] Ledger · Receipt · Drag and drop an image file onto drop zone · _DropTarget (desktop_drop DropTarget)
- [ ] Ledger · Receipt · Drop zone highlights while dragging over · _DropTarget dragging state
- [ ] Ledger · Receipt · Highlight clears when pointer leaves drop zone · _DropTarget MouseRegion onExit
- [ ] Ledger · Receipt · Click drop zone to browse for an image · _DropTarget InkWell → ImagePicker gallery
- [ ] Ledger · Receipt · Thumbnail preview of staged image · _DropTarget Image.memory
- [ ] Ledger · Receipt · Empty prompt "Drop a receipt image here / or click to browse" · _DropTarget
- [ ] Ledger · Receipt · Error "Couldn't read that file." · _pickFile catch
- [ ] Ledger · Receipt · Scan button disabled until image staged · AlertDialog actions, FilledButton "Scan"
- [ ] Ledger · Receipt · Scan shows spinner; Cancel/Scan disabled while busy · FilledButton/TextButton
- [ ] Ledger · Receipt · Success closes dialog, hands result to confirm flow · _scan (ReceiptScanOutcome.seeded)
- [ ] Ledger · Receipt · Error: not a receipt · _messageFor notReceipt
- [ ] Ledger · Receipt · Error: daily AI limit reached · _messageFor rateLimited
- [ ] Ledger · Receipt · Error: network error · _messageFor networkError
- [ ] Ledger · Receipt · Error: needs Cloud AI / sign in · _messageFor unavailable
- [ ] Ledger · Receipt · Error: couldn't read receipt (server/failed) · _messageFor serverError/failed
- [ ] Ledger · Receipt · Helper text: amount/merchant shown for confirmation first · AlertDialog content Text
- [ ] Ledger · Receipt · Cancel closes dialog · TextButton "Cancel"

### Add / Edit Transaction dialog
- [ ] Ledger · Add dialog · Title "Add Transaction" vs "Edit Transaction" · _AddTransactionDialog header
- [ ] Ledger · Add dialog · Close (×) button · IconButton close (tooltip "Close")
- [ ] Ledger · Add dialog · Click outside to dismiss · showDialog barrierDismissible
- [ ] Ledger · Add dialog · Type segments Expense / Income / Transfer · _ModalTypeSegments InkWell
- [ ] Ledger · Add dialog · Changing type clears the chosen category · _setType
- [ ] Ledger · Add dialog · Amount field (₱ prefix, digits and "." only) · _amountField TextFormField
- [ ] Ledger · Add dialog · Amount errors "Enter an amount" / "Must be > 0" · _amountField validator
- [ ] Ledger · Add dialog · Date field opens date picker · _dateField InkWell → showDatePicker
- [ ] Ledger · Add dialog · Account dropdown (searchable, color dots) · _accountDropdown WebSearchableDropdown
- [ ] Ledger · Add dialog · Account label becomes "From Account" for transfers · _accountDropdown label
- [ ] Ledger · Add dialog · "To Account" dropdown (transfer only) · _accountDropdown
- [ ] Ledger · Add dialog · Category dropdown filtered to income/expense · _categoryDropdown WebSearchableDropdown
- [ ] Ledger · Add dialog · Category hint "No categories" when none exist · _categoryDropdown hintText
- [ ] Ledger · Add dialog · Errors "Select an account" / "Select a category" · _decoratedField error
- [ ] Ledger · Add dialog · Description field (max 60 chars) · TextFormField
- [ ] Ledger · Add dialog · Description error "Enter a description" (not for transfer) · TextFormField validator
- [ ] Ledger · Add dialog · Notes (optional) multi-line field · TextFormField maxLines 2
- [ ] Ledger · Add dialog · Prefill from assistant/receipt (type, account, category, amount, description, reimbursable) · initState prefill
- [ ] Ledger · Add dialog · Edit mode loads values (transfer: both legs' accounts) · _initFromExisting
- [ ] Ledger · Add dialog · Installment · Toggle "Split into installments" (credit account + expense only) · _installmentSection Switch
- [ ] Ledger · Add dialog · Installment · Edit wording "Convert to installments" · _installmentSection
- [ ] Ledger · Add dialog · Installment · Pick duration 3 / 6 / 12 / 24 months · _installmentSection InkWell chips
- [ ] Ledger · Add dialog · Installment · Pick interest/mo 0 / 1 / 1.5 / 2 / 3% · _installmentSection InkWell chips
- [ ] Ledger · Add dialog · Installment · Preview "≈ ₱X / month for N months" · _installmentSection summary
- [ ] Ledger · Add dialog · Installment · Preview total interest and total payable (if rate > 0) · _installmentSection summary
- [ ] Ledger · Add dialog · Installment · Turning split on turns reimbursable off and hides it · Switch onChanged
- [ ] Ledger · Add dialog · Reimbursable · Toggle "I'll get this back" (expense only) · _reimbursableSection Switch
- [ ] Ledger · Add dialog · Reimbursable · Pick "Expected back by" date (default ASAP) · _reimbursableSection InkWell → showDatePicker
- [ ] Ledger · Add dialog · Reimbursable · Clear payback date back to ASAP (×) · _reimbursableSection InkWell close icon
- [ ] Ledger · Add dialog · Reimbursable · "Who owes you? (optional)" field (max 40) · _reimbursableSection TextFormField
- [ ] Ledger · Add dialog · Cancel button · TextButton "Cancel"
- [ ] Ledger · Add dialog · Submit label: Add Transaction / Add Installment / Save Changes / Convert to Installments · FilledButton.icon
- [ ] Ledger · Add dialog · Submit shows spinner; buttons disabled while saving · FilledButton.icon _isSubmitting
- [ ] Ledger · Add dialog · Edit transfer can convert to income/expense, or the reverse · _submit
- [ ] Ledger · Add dialog · Turning split off converts an installment back to a normal expense · _submit convertInstallmentPurchaseToRegular
- [ ] Ledger · Add dialog · Opened from the Bills statement breakdown line (showWebEditTransactionDialog) · web_statement_breakdown_dialog.dart → showWebEditTransactionDialog

## Bills

### Header and month stepper
- [ ] Bills · Page title "Bills" with "N bills due, M to receive" subtitle · WebPageHeader (_Header)
- [ ] Bills · Go to previous month · WebMonthStepper chevron IconButton, tooltip "Previous month"
- [ ] Bills · Go to next month · WebMonthStepper chevron IconButton, tooltip "Next month"
- [ ] Bills · Month label shows selected month · WebMonthStepper label
- [ ] Bills · Open Add Bill dialog from header (v2: one Add ▾ menu with Bill / Receivable / Set-aside / Installment) · _Header FilledButton.icon "Add Bill"

### Due-soon heroes
- [ ] Bills · Show up to 4 imminent unpaid bill heroes (v2: one hero, the rest in a "Due soon" group at the top of the list) · _DueSoonRow (DueSoonHero tiles, 2-up ≥860px else 1-up, odd last tile centred)
- [ ] Bills · Hero shows due label, overdue styling, name, subtitle, amount · DueSoonHero
- [ ] Bills · Mark bill paid from hero (opens Settle dialog) · DueSoonHero FilledButton "Mark paid"
- [ ] Bills · Edit bill from hero · DueSoonHero IconButton, tooltip "Edit bill"
- [ ] Bills · Hero row hidden when nothing imminent · _BillsBody (conditional)

### Stat strip (totals)
- [ ] Bills · "Due This Month" total + unpaid count (red when >0) · _StatStrip WebStatTile
- [ ] Bills · "Paid" total + settled count · _StatStrip WebStatTile
- [ ] Bills · "Total This Month" total + bill count · _StatStrip WebStatTile
- [ ] Bills · "To Receive" total + pending count · _StatStrip WebStatTile
- [ ] Bills · Stat strip 4 columns ≥760px, else 2 (v2: side column "This month") · _StatStrip LayoutBuilder

### Coming up
- [ ] Bills · View merged timeline (bills/receivables/set-asides/installments) · _ComingUpCard (ComingUpTimeline)
- [ ] Bills · Card description "Next N across bills, receivables…" · _ComingUpCard WebCard description
- [ ] Bills · Inflow rows shown with arrow dot and "+" green amount · ComingUpTimeline _TimelineRow
- [ ] Bills · Click bill timeline row opens Edit Bill dialog · ComingUpTimeline InkWell onTap
- [ ] Bills · Click receivable timeline row opens Edit Receivable · ComingUpTimeline InkWell onTap
- [ ] Bills · Click set-aside timeline row opens Edit Set-Aside · ComingUpTimeline InkWell onTap
- [ ] Bills · Click installment timeline row opens Edit Installment · ComingUpTimeline InkWell onTap
- [ ] Bills · Coming up card hidden when empty · _BillsBody (conditional)

### Credit cards
- [ ] Bills · Credit Cards card with "Total owed ₱X · pay anytime" / "No outstanding balance" · _WebCreditCardsCard
- [ ] Bills · Per-card "Owe ₱X" / "Clear" badge · _WebCreditCardRow WebBadge
- [ ] Bills · Utilization bar (colour at 70%/90%) + "₱X avail." or "% used" · _WebCreditCardRow LinearProgressIndicator
- [ ] Bills · "No credit limit set" / "No balance" text when no limit · _WebCreditCardRow
- [ ] Bills · Open Pay card dialog · _WebCreditCardRow FilledButton "Pay Now" (only when balance >0)
- [ ] Bills · Empty state "No credit card accounts." · _WebCreditCardsCard _EmptyHint
- [ ] Bills · Credit Cards card hidden when no credit accounts · _BillsBody (conditional)

### Pay card dialog (Bills page, private _WebQuickPayDialog — v2: SettleKind.cardPayment of the unified Settle dialog)
- [ ] Bills · Pay card dialog titled "Pay <card>" · _WebQuickPayDialog AlertDialog
- [ ] Bills · Edit amount (prefilled with payable, autofocus) · _WebQuickPayDialog TextFormField "Amount"
- [ ] Bills · Validation "Must be > 0" on amount · _WebQuickPayDialog amount validator
- [ ] Bills · Choose "Pay from" account (active non-liability) · _WebQuickPayDialog DropdownButtonFormField
- [ ] Bills · Validation "Select an account" · _WebQuickPayDialog dropdown validator
- [ ] Bills · "No liquid accounts available." error when none · _WebQuickPayDialog
- [ ] Bills · Change payment date (picker up to tomorrow) · _WebQuickPayDialog TextButton "Change" + "Date: yyyy-mm-dd"
- [ ] Bills · Cancel pay dialog · _WebQuickPayDialog TextButton "Cancel"
- [ ] Bills · Submit payment (spinner while saving; disabled with no account) · _WebQuickPayDialog FilledButton "Pay"
- [ ] Bills · Success toast "Paid ₱X to <card>." · AppToast.success
- [ ] Bills · Error toast "Could not record payment: …" · AppToast.error
- [ ] Bills · Unified dialog must keep the shared quick-pay checks the Dashboard has today (over-owed, over-balance, summary line) · widgets/web_quick_pay_dialog.dart (Dashboard-only today)

### Upcoming card (unpaid bills)
- [ ] Bills · Upcoming card with "₱X across N bills" description · _UpcomingCard WebCard
- [ ] Bills · Open Add Bill dialog from card · _UpcomingCard header TextButton.icon "Add bill"
- [ ] Bills · Start batch selection for bills · _UpcomingCard header WebBatchSelectControl "Select"
- [ ] Bills · Empty state "No bills due — you are all caught up." · _UpcomingCard _EmptyHint
- [ ] Bills · Batch bar still shows when the unpaid list is empty · _UpcomingCard
- [ ] Bills · "DUE" footer total · _UpcomingCard footer row
- [ ] Bills · Upcoming and Set-asides side by side ≥900px, stacked below (v2: tabs) · _SideBySideCards

### Bill row (Upcoming and Paid cards)
- [ ] Bills · Tick checkbox to mark bill paid (opens Settle dialog) · _BillRow _PaidCheckbox, tooltip "Mark paid"
- [ ] Bills · Untick paid checkbox to undo payment · _BillRow _PaidCheckbox, tooltip "Mark unpaid"
- [ ] Bills · Category badge / account badge for statements · _BillRow CategoryBadge / AccountBadge
- [ ] Bills · Name (struck through when paid) + type badge · _BillRow WebBadge
- [ ] Bills · Subtitle: due day, account, progress note · _BillRow subtitle
- [ ] Bills · Statement row shows "<card> statement", period, due, composition · _BillRow (statementCard)
- [ ] Bills · Statement amount with caption + minimum label · _BillRow statement amount column
- [ ] Bills · Open statement items breakdown · _BillRow TextButton.icon "<itemsLabel>" (statements only)
- [ ] Bills · Open row actions menu · _RowActions PopupMenuButton ⋮, tooltip "Actions"
- [ ] Bills · Menu: Mark unpaid (when undoable) · _RowActions PopupMenuItem
- [ ] Bills · Menu: Edit bill · _RowActions PopupMenuItem "Edit"
- [ ] Bills · Menu: Delete bill (red) · _RowActions PopupMenuItem "Delete"
- [ ] Bills · In select mode, checkbox becomes selection box; menu and items link hidden · _BillRow WebRowSelectBox
- [ ] Bills · Toast "Marked "<name>" unpaid." · AppToast after undo
- [ ] Bills · Toast "Deleted "<name>"." · AppToast after delete
- [ ] Bills · A bill appears in exactly one list place besides the hero (v2 acceptance; today it can show in hero, Upcoming and Coming up) · _BillsBody

### Delete bill / receivable / set-aside confirms ("which ones?")
- [ ] Bills · One-off delete confirm "Delete <x>?" (Cancel / Delete) · confirmRecurringDelete → AppConfirmDialog
- [ ] Bills · Recurring delete asks scope, says earlier months stay · confirmRecurringDelete _askScope
- [ ] Bills · Recurring delete: Cancel · _askScope TextButton "Cancel"
- [ ] Bills · Recurring delete: "This month only" · _askScope TextButton
- [ ] Bills · Recurring delete: "All months" (red) · _askScope FilledButton

### Undo settlement confirm (single and batch)
- [ ] Bills · Undo dialog title (Undo payment/receipt/funding?) + "goes back to open" text · showUndoSettlementDialog
- [ ] Bills · Toggle "Also remove the ledger transaction" (shown when linked) · showUndoSettlementDialog CheckboxListTile
- [ ] Bills · Subtitle shows balance effect or "transaction stays" · showUndoSettlementDialog
- [ ] Bills · Plain note when no ledger entry (installments) · showUndoSettlementDialog
- [ ] Bills · Cancel undo · showUndoSettlementDialog TextButton "Cancel"
- [ ] Bills · Confirm undo · showUndoSettlementDialog FilledButton "Undo"

### Settle dialog (Mark paid / received / Fund / installment)
- [ ] Bills · Settle dialog with title + summary text · _WebSettleDialog AlertDialog
- [ ] Bills · Edit amount (autofocus, ₱ prefix) · Settle TextFormField (Amount paid/received/to set aside)
- [ ] Bills · Helper shows "Scheduled: ₱X" or "Monthly: ₱X" · Settle amount helperText
- [ ] Bills · Validation "Enter an amount" · Settle amount validator
- [ ] Bills · Pick account showing balance (Pay from/Deposit to/Fund from) · Settle DropdownButtonFormField
- [ ] Bills · Pick "Set aside into" destination or "Spend it (no transfer)" · Settle destination dropdown (set-asides)
- [ ] Bills · Destination hint "Choose where it goes"; Fund disabled until chosen · Settle destination dropdown
- [ ] Bills · Destination list excludes the funding account; resets on conflict · Settle destination dropdown
- [ ] Bills · Pick settle date (back-datable) · Settle InputDecorator/InkWell date field
- [ ] Bills · Toggle "Already added to ledger" (hides account picker) · Settle CheckboxListTile (bills/receivables)
- [ ] Bills · Empty-accounts error message in red · Settle emptyAccountsMessage text
- [ ] Bills · Confirm disabled without required account · Settle FilledButton state
- [ ] Bills · Cancel settle · Settle TextButton "Cancel"
- [ ] Bills · Confirm settle (Mark paid/Mark received/Fund) with spinner · Settle FilledButton
- [ ] Bills · Error toast "Could not <verb>: …", dialog stays open · Settle AppToast.error
- [ ] Bills · Bill paid toast "Paid ₱X for "<name>" from <acct>." / "Marked … paid." · _markBillPaidFlow AppToast.success
- [ ] Bills · Installment settle has no account picker (charge rides on the card) · _InstallmentRow → Settle (installment kind)

### Paid card
- [ ] Bills · Paid card with "₱X settled" (v2: Paid tab with count) · _PaidCard WebCard
- [ ] Bills · Paid bill rows join the bills selection (no Select of their own) · _PaidCard _BillRow selection
- [ ] Bills · Paid card hidden when nothing paid · _BillsBody (conditional)

### Budgeted Set-Asides card
- [ ] Bills · Set-asides card "Savings, sinking funds & one-off plans" (v2: Set-asides tab) · _BudgetedExpensesCard WebCard
- [ ] Bills · Open Add Set-Aside dialog · _BudgetedExpensesCard header OutlinedButton.icon "Add Set-Aside"
- [ ] Bills · Start batch selection for set-asides · _BudgetedExpensesCard header WebBatchSelectControl "Select"
- [ ] Bills · Empty state "No set-asides budgeted this month." · _BudgetedExpensesCard _EmptyHint
- [ ] Bills · Unfunded first, funded below (struck through) · _BudgetedExpensesCard ordering
- [ ] Bills · "TO SET ASIDE" footer total · _BudgetedExpensesCard footer
- [ ] Bills · Row subtitle: type · note · account · _BudgetedExpenseRow
- [ ] Bills · Tick checkbox to fund (opens Settle dialog) · _BudgetedExpenseRow _PaidCheckbox, tooltip "Mark funded"
- [ ] Bills · Untick to undo funding · _BudgetedExpenseRow _PaidCheckbox, tooltip "Mark unfunded"
- [ ] Bills · Error toast "Add an account before funding." · _markFunded AppToast.error
- [ ] Bills · Fund toast "Transferred …" / "Set aside …" · _markFunded AppToast.success
- [ ] Bills · Menu: Mark unfunded / Edit / Delete · _BudgetedExpenseRow _RowActions ⋮
- [ ] Bills · Toasts "Marked … unfunded." / "Deleted …" · AppToast

### By Account card
- [ ] Bills · By Account card "How much to move into each account…" · _ByAccountCard WebCard
- [ ] Bills · Per-account row: item count, bills ₱, set-asides ₱, total · _ByAccountRow
- [ ] Bills · "Unassigned" row with "no account set" · _ByAccountRow
- [ ] Bills · "TOTAL TO MOVE" footer · _ByAccountCard footer
- [ ] Bills · By Account hidden when nothing outstanding · _BillsBody (conditional)

### Receivables card
- [ ] Bills · Receivables card "Money owed to you" (v2: Receivables tab) · _ReceivablesCard WebCard
- [ ] Bills · Open Add Receivable dialog · _ReceivablesCard header OutlinedButton.icon "Add Receivable"
- [ ] Bills · Start batch selection for receivables · _ReceivablesCard header WebBatchSelectControl "Select"
- [ ] Bills · Empty state "Nothing owed to you this month." · _ReceivablesCard _EmptyHint
- [ ] Bills · Pending first, received below (struck through) · _ReceivablesCard ordering
- [ ] Bills · "PENDING" footer total · _ReceivablesCard footer
- [ ] Bills · Row subtitle "Due Nth"/"ASAP" · type · _ReceivableRow
- [ ] Bills · Tick checkbox to mark received (opens Settle dialog) · _ReceivableRow _PaidCheckbox, tooltip "Mark received"
- [ ] Bills · Untick to undo receipt · _ReceivableRow _PaidCheckbox, tooltip "Mark not received"
- [ ] Bills · Received toast "Received ₱X … into <acct>." / "Marked … received." · AppToast.success
- [ ] Bills · Menu: Mark not received / Edit / Delete · _ReceivableRow _RowActions ⋮
- [ ] Bills · Toasts "Marked … not received." / "Deleted …" · AppToast

### Installments card
- [ ] Bills · Installments card "₱X due across N plans" / "No payments due" (v2: Installments tab) · _InstallmentsCard WebCard
- [ ] Bills · Open Add Installment dialog · _InstallmentsCard header OutlinedButton.icon "Add Installment"
- [ ] Bills · Start batch selection for installments · _InstallmentsCard header WebBatchSelectControl "Select"
- [ ] Bills · Empty state "No installment payments due this month." · _InstallmentsCard _EmptyHint
- [ ] Bills · "MONTHLY LOAD" footer paid/total · _InstallmentsCard footer
- [ ] Bills · Row: name, "count/total" badge, progress bar, detail line · _InstallmentRow
- [ ] Bills · Tick to mark installment paid (Settle, no account picker) · _InstallmentRow _PaidCheckbox (tooltip from presenter)
- [ ] Bills · Untick to undo this month's payment · _InstallmentRow _PaidCheckbox
- [ ] Bills · Checkbox inert for plans paid via statement · _InstallmentRow _PaidCheckbox (onTap null)
- [ ] Bills · Open linked statement breakdown · _InstallmentRow TextButton.icon "<linkLabel>"
- [ ] Bills · Menu: Mark unpaid this month / Edit / Delete · _InstallmentRow _RowActions ⋮
- [ ] Bills · "Delete installment?" confirm with Cancel / red Delete · _InstallmentRow _delete AlertDialog
- [ ] Bills · Toasts "Recorded ₱X …", "Marked … unpaid this month.", "Deleted …" · AppToast

### Batch select and batch bar (per card / per tab)
- [ ] Bills · "Select" disabled when list empty or another card selecting · WebBatchSelectControl TextButton.icon
- [ ] Bills · "N selected" count in card header · WebBatchSelectControl
- [ ] Bills · Toggle Select all / Clear all · WebBatchSelectControl TextButton
- [ ] Bills · Cancel selection mode · WebBatchSelectControl TextButton "Cancel"
- [ ] Bills · Tick/untick row in selection; empty selection exits · WebRowSelectBox Checkbox
- [ ] Bills · Batch bar "N selected" under card · WebBatchBar
- [ ] Bills · Batch settle (Pay N / Receive N / Fund N) · WebBatchBar FilledButton.icon
- [ ] Bills · Batch undo "Undo N" · WebBatchBar OutlinedButton.icon
- [ ] Bills · Batch delete "Delete N" (red) · WebBatchBar OutlinedButton.icon
- [ ] Bills · Batch buttons disabled at 0 count or while busy · WebBatchBar enabled state
- [ ] Bills · Batch delete confirm (plain or "This month only / All months") · confirmRecurringBatchDelete
- [ ] Bills · Batch result toast incl. "N couldn't be done — check their accounts." · _finishBatch AppToast
- [ ] Bills · Batch fund error "Add an account before funding." · _batchFundExpenses AppToast.error

### Batch settle dialog (v2: the unified Settle dialog with targets > 1)
- [ ] Bills · Batch title (Mark N bills paid / received / Fund / Pay) + subtitle · _WebBatchSettleDialog
- [ ] Bills · Toggle "Already added to ledger" (bills/receivables) · Batch CheckboxListTile
- [ ] Bills · Pick shared account with balances · Batch DropdownButtonFormField (Pay from/Deposit into/Fund from)
- [ ] Bills · Warning "No account can cover this whole selection…" · Batch red text
- [ ] Bills · Toggle "X of N have their own destination" · Batch CheckboxListTile (set-asides)
- [ ] Bills · Pick "Set (the other N) aside into" or "Spend it" · Batch destination dropdown
- [ ] Bills · Pick batch date · Batch InputDecorator/InkWell "Date"
- [ ] Bills · Cancel batch settle · Batch TextButton "Cancel"
- [ ] Bills · Confirm (Mark N paid / received / Fund N / Pay N), disabled until valid · Batch FilledButton

### Add/Edit Bill dialog
- [ ] Bills · Dialog title "Add Bill" / "Edit Bill" · _AddBillDialog AlertDialog
- [ ] Bills · Enter name (autofocus), "Enter a name" validation · _AddBillDialog TextFormField "Name"
- [ ] Bills · Choose bill type (7 options) · _AddBillDialog Dropdown "Type"
- [ ] Bills · Enter amount, "Must be > 0" validation · _AddBillDialog TextFormField "Amount"
- [ ] Bills · Enter due day, "1–31" validation; Enter submits · _AddBillDialog TextFormField "Due day (1–31)"
- [ ] Bills · Choose payment account (optional, None) · _AddBillDialog Dropdown "Payment account (optional)"
- [ ] Bills · Choose expense category (optional, None) · _AddBillDialog Dropdown "Category (optional)"
- [ ] Bills · Enter payment note (optional) · _AddBillDialog TextFormField "Payment note (optional)"
- [ ] Bills · Toggle Recurring "Auto-generate next month" · _AddBillDialog SwitchListTile
- [ ] Bills · Choose recurrence Monthly/Weekly/Yearly/Custom · _AddBillDialog Dropdown "Recurrence"
- [ ] Bills · Toggle "Apply to future months" / "Also drop future months" · RecurringScopeField Switch
- [ ] Bills · Toggle "Remind me before due" (bell icon) · _AddBillDialog SwitchListTile
- [ ] Bills · Choose reminder lead 1/2/3/5/7 days · _AddBillDialog ChoiceChips
- [ ] Bills · Hint "Add an account or category in the app…" · _AddBillDialog text
- [ ] Bills · Cancel / submit "Add Bill"/"Save" with spinner · _AddBillDialog actions
- [ ] Bills · Error toast "Could not save bill: …" · AppToast.error

### Add/Edit Receivable dialog
- [ ] Bills · Dialog title "Add Receivable" / "Edit Receivable" · _ReceivableDialog
- [ ] Bills · Enter name (autofocus), required · _ReceivableDialog TextFormField "Name"
- [ ] Bills · Choose type Salary/Reimbursement/Business/Other · _ReceivableDialog Dropdown "Type"
- [ ] Bills · Enter amount, "Must be > 0" · _ReceivableDialog TextFormField "Amount"
- [ ] Bills · Pick expected date (default today) · _ReceivableDialog InkWell date field "Expected date"
- [ ] Bills · Choose deposit account (optional) · _ReceivableDialog Dropdown "Deposit account (optional)"
- [ ] Bills · Choose income category (optional) · _ReceivableDialog Dropdown "Category (optional)"
- [ ] Bills · Toggle Recurring + choose recurrence · _ReceivableDialog SwitchListTile + Dropdown
- [ ] Bills · Toggle apply-to-future scope · RecurringScopeField Switch
- [ ] Bills · Hint "Add an account or income category…" · _ReceivableDialog text
- [ ] Bills · Cancel / submit "Add Receivable"/"Save"; error toast · _ReceivableDialog actions

### Add/Edit Set-Aside dialog
- [ ] Bills · Dialog title "Add Set-Aside" / "Edit Set-Aside" · _BudgetedExpenseDialog
- [ ] Bills · Enter name (autofocus), required · _BudgetedExpenseDialog TextFormField "Name (e.g. Travel Fund…)"
- [ ] Bills · Choose set-aside type · _BudgetedExpenseDialog Dropdown "Type"
- [ ] Bills · Enter amount, "Must be > 0" · _BudgetedExpenseDialog TextFormField "Amount"
- [ ] Bills · Enter note; Enter submits · _BudgetedExpenseDialog TextFormField "Note (optional…)"
- [ ] Bills · Choose fund-from liquid account (optional) · _BudgetedExpenseDialog Dropdown "Fund from account (optional)"
- [ ] Bills · Choose destination or "Decide when funding" · _BudgetedExpenseDialog Dropdown "Set aside into (optional)"
- [ ] Bills · Choose category (optional) · _BudgetedExpenseDialog Dropdown "Category (optional)"
- [ ] Bills · Toggle Recurring + recurrence + scope · _BudgetedExpenseDialog SwitchListTile/Dropdown/RecurringScopeField
- [ ] Bills · Note "Funding a set-aside later debits a liquid account…" · _BudgetedExpenseDialog text
- [ ] Bills · Cancel / submit "Add Set-Aside"/"Save"; error toast · _BudgetedExpenseDialog actions

### Add/Edit Installment dialog
- [ ] Bills · Dialog title "Add Installment" / "Edit Installment" · _InstallmentDialog
- [ ] Bills · Enter name (autofocus), required · _InstallmentDialog TextFormField "Name (e.g. MacBook Pro…)"
- [ ] Bills · Choose credit/BNPL account, "Select an account" · _InstallmentDialog Dropdown "Account (Credit / BNPL)"
- [ ] Bills · Red notice when no credit/BNPL accounts exist · _InstallmentDialog text
- [ ] Bills · Pick purchase date · _InstallmentDialog InkWell date field
- [ ] Bills · Read statement-cycle hint · _InstallmentDialog info box (_buildCycleHint)
- [ ] Bills · Choose deferral None/1mo/2mo/3mo · _InstallmentDialog ChoiceChips
- [ ] Bills · Enter total amount, "Must be > 0" · _InstallmentDialog TextFormField "Total amount"
- [ ] Bills · Choose months 3/6/12/24 · _InstallmentDialog ChoiceChips
- [ ] Bills · Enter custom months · _InstallmentDialog TextFormField "Custom"
- [ ] Bills · Choose interest-rate preset · _InstallmentDialog ChoiceChips (ratePresets)
- [ ] Bills · Enter custom interest % · _WebCustomRateField "Custom %"
- [ ] Bills · Read interest preview summary · _InstallmentDialog percent info box
- [ ] Bills · Edit auto-computed monthly payment, "Must be > 0" · _InstallmentDialog TextFormField "Monthly payment (auto, editable)"
- [ ] Bills · Step start month back / forward · _InstallmentDialog IconButtons, tooltips "Previous month"/"Next month"
- [ ] Bills · Enter note; Enter submits · _InstallmentDialog TextFormField "Note (optional…)"
- [ ] Bills · Cancel / submit "Add Installment"/"Save"; error toast · _InstallmentDialog actions

### Statement breakdown dialog
- [ ] Bills · Statement dialog header: bill name + due label · WebStatementBreakdownDialog _Header
- [ ] Bills · Close statement dialog · _Header IconButton, tooltip "Close"
- [ ] Bills · Click outside dialog to dismiss · showDialog barrierDismissible
- [ ] Bills · Unpaid amount headline; Bill amount / Repaid / Unpaid rows · _Body _Outlined summary
- [ ] Bills · Unreconciled note under summary · _Body
- [ ] Bills · "Transaction total: N items" + period label · _Body
- [ ] Bills · "Carried over from last statement" row · _Body _AmountRow
- [ ] Bills · Sections (Purchases/Installments/Refunds/Repaid) with count + total · _Body sections
- [ ] Bills · Click a line to open the ledger's Edit Transaction dialog · StatementLineRow onTap → showWebEditTransactionDialog
- [ ] Bills · Figures update live after an edit · ListenableBuilder (presenter + ledger)
- [ ] Bills · Empty state "No statement cycle" · AppEmptyState
- [ ] Bills · Empty state "No items in this cycle yet" · AppEmptyState

## Budget

### Page header
- [ ] Budget · See page title with selected month subtitle · WebPageHeader "Budget" ("{Month} · set your allocations")
- [ ] Budget · Open Manage groups dialog · Header trailing, OutlinedButton.icon "Manage groups" (folder icon)
- [ ] Budget · Go to previous month · Header WebMonthStepper, prev IconButton (tooltip "Previous month")
- [ ] Budget · Go to next month · Header WebMonthStepper, next IconButton (tooltip "Next month")
- [ ] Budget · Read current month label in stepper · Header WebMonthStepper label

### Pace ring hero (only shown when the month has rows)
- [ ] Budget · View spent-percentage ring with "% spent" centre · _PaceRingHero, AppRingProgress (128px)
- [ ] Budget · Ring turns error colour when over budget · _PaceRingHero ring primaryColor
- [ ] Budget · View SPENT figure and "of {allocated}" line · _PaceRingHero figure column
- [ ] Budget · View "{amount} left" or "{amount} over" line · _PaceRingHero figure column (green/red)
- [ ] Budget · See Ahead of pace / Over pace / Over budget pill · _PacePill (current month only)
- [ ] Budget · Ring stacks above figure on narrow widths (<460px) · _PaceRingHero LayoutBuilder

### Stat strip — DROPPED by Plan 063 (repeats the hero); the figures must still be readable from the hero
- [ ] Budget · View Allocated figure ("Planned this month") · _StatStrip WebStatTile
- [ ] Budget · View Spent figure with "% used" sub-line · _StatStrip WebStatTile
- [ ] Budget · View Remaining figure (red when negative) · _StatStrip WebStatTile
- [ ] Budget · View Categories count with "{n} groups" · _StatStrip WebStatTile

### Empty state
- [ ] Budget · See "No budget set for this month" empty card · _EmptyState (shown above setup card when no rows)
- [ ] Budget · Add row stays available while the month is empty · _SetupCard always rendered

### Budget Setup card – header
- [ ] Budget · Read edit hint "Click any allocated cell…Enter on the last row to add" · _SetupCard header bar
- [ ] Budget · View total allocated and "{x} left" summary · _SetupCard header bar Text.rich (left turns red when negative)
- [ ] Budget · Scroll the table horizontally on narrow viewports · _SetupCard horizontal SingleChildScrollView (min 920px)

### Budget Setup card – data rows
- [ ] Budget · View category name with colour dot · _DataRow Category cell
- [ ] Budget · See "{in} in · {out} out" sub-line on savings rows with withdrawals · _DataRow Category cell
- [ ] Budget · Change an expense row's group from dropdown · _DataRow Group cell, _GroupDropdown (DropdownButton)
- [ ] Budget · See group colour swatch on each dropdown option · _GroupDropdown items
- [ ] Budget · Savings rows show fixed group label (not editable) · _DataRow Group cell, _GroupLabel
- [ ] Budget · Click Allocated cell to edit the amount · _DataRow Allocated cell, _AmountField TextField
- [ ] Budget · Hover Allocated cell shows edit highlight · _AmountField hoverColor
- [ ] Budget · Focus selects the whole raw amount for overwriting · _AmountField focus listener
- [ ] Budget · Press Enter to commit allocation and blur · _AmountField onSubmitted
- [ ] Budget · Click/tab away commits allocation on blur · _AmountField focus-loss commit
- [ ] Budget · Only digits, dot and comma accepted in amount · _AmountField input formatter
- [ ] Budget · Amount shows thousands separators when not focused · _AmountField display
- [ ] Budget · View Spent amount per row · _DataRow Spent cell
- [ ] Budget · View Remaining per row (red when negative) · _DataRow Remaining cell
- [ ] Budget · View Used progress bar and percentage · _DataRow Used cell, WebProgressBar
- [ ] Budget · See status badge On track / Watch / Over · _DataRow Status cell, WebBadge (expense rows)
- [ ] Budget · See status badge On track / Funded on savings rows · _DataRow Status cell, WebBadge (savings rows never red)
- [ ] Budget · Remove a row from the budget · _DataRow action cell, IconButton "×" (tooltip "Remove from budget")
- [ ] Budget · Confirm removal in "Remove from budget?" dialog · _confirmRemove AlertDialog, FilledButton "Remove" (error colour)
- [ ] Budget · Cancel removal · _confirmRemove AlertDialog, TextButton "Cancel"
- [ ] Budget · See "Removed "{name}" from the budget." toast (no Undo) · AppToast.show after remove
- [ ] Budget · Rows grouped by budget group (v2: with subtotal rows per group) · _SetupCard group sections

### Budget Setup card – add row
- [ ] Budget · Switch add-row to Expense mode · _AddModeToggle segment "Expense" (InkWell)
- [ ] Budget · Switch add-row to Savings mode · _AddModeToggle segment "Savings" (InkWell)
- [ ] Budget · Switching mode clears the picked category/account · _AddRow _setSavingsMode
- [ ] Budget · Open searchable category picker · _AddRow WebSearchableDropdown (hint "Choose a category…")
- [ ] Budget · Open searchable savings account picker · _AddRow WebSearchableDropdown (hint "Choose an account…")
- [ ] Budget · Type to filter picker options · WebSearchableDropdown overlay search field
- [ ] Budget · Press Enter in picker search to pick first match · WebSearchableDropdown search onSubmitted
- [ ] Budget · Press Esc to close picker · WebSearchableDropdown search FocusNode key handler
- [ ] Budget · Click outside to close picker · WebSearchableDropdown overlay barrier
- [ ] Budget · See "No matches" when filter finds nothing · WebSearchableDropdown list empty state
- [ ] Budget · Picker lists only categories not yet budgeted · _AddRow _availableCategories
- [ ] Budget · Picker lists only savings/goal accounts not yet budgeted · _AddRow _availableSavingsTargets
- [ ] Budget · Savings option shows "· goal {target}" suffix · _savingsAccountLabel
- [ ] Budget · Choose "＋ New category…" to create a category · _AddRow picker first entry
- [ ] Budget · Type new category name in dialog · "New Expense Category" AlertDialog, TextField "Category name"
- [ ] Budget · Icon preview tracks the typed name live · "New Expense Category" dialog, WebCategoryIconPreview
- [ ] Budget · Click icon preview to pick a category icon · "New Expense Category" dialog, WebCategoryIconPreview (tooltip "Choose category icon")
- [ ] Budget · Press Enter to create the category · "New Expense Category" TextField onSubmitted
- [ ] Budget · Create category via button · "New Expense Category" TextButton "Create"
- [ ] Budget · Cancel creating a category · "New Expense Category" TextButton "Cancel"
- [ ] Budget · Empty name is ignored on Create/Enter · "New Expense Category" build() guard
- [ ] Budget · New category becomes the picked add-row value · _AddRow _onPick
- [ ] Budget · Choose group for new expense budget · _AddRow _GroupDropdown
- [ ] Budget · Savings mode shows fixed Savings group label · _AddRow _GroupLabel
- [ ] Budget · Type allocation amount for new row · _AddRow amount TextField (hint "0")
- [ ] Budget · Press Enter in amount to add the row · _AddRow amount TextField onSubmitted
- [ ] Budget · Click check button to add the row · _AddRow IconButton ✓ (tooltip "Add category" / "Add savings goal")
- [ ] Budget · Add does nothing when no category picked · _AddRow _add guard
- [ ] Budget · See spinner while row is being added · _AddRow _busy CircularProgressIndicator
- [ ] Budget · Add row resets picker and amount, keeps mode · _AddRow _add post-save

### Allocation by Group card (only shown when rows exist)
- [ ] Budget · View group donut with "Allocated" centre total · _AllocationByGroup WebDonutChart (no legend, no hover)
- [ ] Budget · See "No data" in donut when totals are zero · WebDonutChart empty state
- [ ] Budget · View per-group legend: name, allocated amount · _GroupLegendItem
- [ ] Budget · View per-group spent progress bar · _GroupLegendItem WebProgressBar
- [ ] Budget · View "{spent} spent · {n}% of budget" line · _GroupLegendItem caption
- [ ] Budget · Legend goes two-column and beside donut when ≥720px · _AllocationByGroup/_GroupLegendGrid
- [ ] Budget · Card subtitle "Updates as you edit" (live refresh) · _AllocationByGroup WebCard description
- [ ] Budget · Donut animates in on load (no hover/tooltip) · WebDonutChart animation

### Manage groups dialog
- [ ] Budget · View list of budget groups · "Budget groups" AlertDialog ListView
- [ ] Budget · See "Savings group" / "Built-in" role subtitle · Group ListTile subtitle
- [ ] Budget · Rename a group · Group ListTile, IconButton pencil (tooltip "Rename")
- [ ] Budget · Delete a custom group · Group ListTile, IconButton trash (tooltip "Delete"; hidden on built-in)
- [ ] Budget · Add a new group · OutlinedButton.icon "Add group"
- [ ] Budget · Close manage groups dialog · FilledButton "Done"
- [ ] Budget · Type group name in New group prompt · "New group" AlertDialog TextField "Group name"
- [ ] Budget · Confirm new group · "New group" FilledButton "Add"
- [ ] Budget · Press Enter to confirm group name · Name prompt TextField onSubmitted
- [ ] Budget · Cancel group name prompt · Name prompt TextButton "Cancel"
- [ ] Budget · Edit name in Rename group prompt (prefilled) · "Rename group" AlertDialog TextField
- [ ] Budget · Save renamed group · "Rename group" FilledButton "Save"
- [ ] Budget · Blank group name is rejected silently · Name prompt trim/empty guard
- [ ] Budget · Confirm group deletion (budgets move to first group) · "Delete group?" AlertDialog FilledButton "Delete" (error colour)
- [ ] Budget · Cancel group deletion · "Delete group?" TextButton "Cancel"
- [ ] Budget · List refreshes live after add/rename/delete · Dialog ListenableBuilder

### Category icon picker (opened from Budget)
- [ ] Budget · Pick "Auto" (name-derived) icon · "Choose an icon" dialog, _IconChoice "Auto"
- [ ] Budget · Pick an icon from grouped catalog · "Choose an icon" dialog, _IconChoice grid per group
- [ ] Budget · See current icon highlighted · _IconChoice selected state
- [ ] Budget · Cancel icon picker · "Choose an icon" TextButton "Cancel"

## History

### Page states
- [ ] History · See loading spinner while data loads · WebHistoryPage isLoading
- [ ] History · See "No history yet" empty state · _HistoryEmptyState
- [ ] History · View page subtitle with month span · WebPageHeader ("Last N months · span" / "Live month so far")

### Current month (live)
- [ ] History · See "Current month" header with Live badge · WebSectionHeader
- [ ] History · View live month summary card · MonthlySummaryCard (isLive)
- [ ] History · Click live card to open month detail · MonthlySummaryCard onTap → showWebMonthDetailDialog

### Period stats
- [ ] History · View Ending Cash Change tile · _StatStrip WebStatTile
- [ ] History · View Avg Monthly Net tile · _StatStrip WebStatTile
- [ ] History · View Avg Savings Rate tile · _StatStrip WebStatTile
- [ ] History · View Avg Saved / mo tile · _StatStrip WebStatTile
- [ ] History · View Best Month tile with net · _StatStrip WebStatTile
- [ ] History · Tiles reflow 4/2/1-up, short row centred (v2: one row of 5) · _StatStrip WebTileFlow

### Charts
- [ ] History · View Cash Flow Trend (income/expenses/net lines) · WebCard "Cash Flow Trend", WebMultiLineChart
- [ ] History · Hover a point to read each series value · WebMultiLineChart line tooltip ("{series}  {value}")
- [ ] History · See static series legend (Income/Expenses/Net) · WebMultiLineChart _LegendDot row (not toggleable)
- [ ] History · View Cumulative Savings area chart · WebCard "Cumulative Savings", WebLineChart
- [ ] History · See cumulative total badge (up/down) · Cumulative Savings card trailing WebBadge
- [ ] History · Hover cumulative chart to read month + value · WebLineChart tooltip
- [ ] History · View Ending Cash Trend area chart · WebCard "Ending Cash Trend", WebLineChart
- [ ] History · See ending cash growth badge (up/down) · Ending Cash Trend card trailing WebBadge
- [ ] History · Hover ending cash chart to read month + value · WebLineChart tooltip
- [ ] History · Paired charts sit side by side at ≥1000px (v2: decided by LayoutBuilder, not window width) · _HistoryBody isWide
- [ ] History · See "No data" in charts when series is empty · WebLineChart/WebMultiLineChart empty state

### Monthly Summary table
- [ ] History · View monthly rows newest-first (Month/Income/Expenses/Net/Rate) · WebCard "Monthly Summary", WebDataTable
- [ ] History · See Live badge on current-month row · Month column cell
- [ ] History · Net shown red when negative · Net column cell
- [ ] History · Hover row shows highlight and pointer cursor · WebDataTable _BodyRow MouseRegion
- [ ] History · Click a row to open month detail · WebDataTable onRowTap → showWebMonthDetailDialog
- [ ] History · See "No months recorded" when table empty · WebDataTable emptyLabel

### Spending by Category card
- [ ] History · View per-category average per month · _CategoryAverages/_CategoryRow
- [ ] History · See latest-vs-average % badge (up/down/neutral) · _CategoryRow WebBadge
- [ ] History · View relative average bar per category · _CategoryRow WebProgressBar
- [ ] History · See "Latest: {amount}" line · _CategoryRow caption
- [ ] History · See "No spending recorded yet." placeholder · _CategoryAverages placeholder
- [ ] History · See "No categorised spending yet." placeholder · _CategoryAverages placeholder

### Month detail dialog
- [ ] History · See month title with Net positive/negative badge · _WebMonthDetailDialog title
- [ ] History · View Cash flow section (income, expenses, net, rate, ending cash) · _Section "Cash flow"
- [ ] History · See "Set aside to savings" when available · _Section "Cash flow" conditional row
- [ ] History · See "Net worth" when available · _Section "Cash flow" conditional row
- [ ] History · View Bills & receivables section · _Section "Bills & receivables"
- [ ] History · View exact per-category spend with share % bar · "Spending by category" _CategoryLine list
- [ ] History · See "No categorised spending this month." · Month detail empty state
- [ ] History · Scroll long month detail content · Dialog SingleChildScrollView
- [ ] History · Close month detail dialog · FilledButton "Close"

## Setup & Accounts

### Page header & states
- [ ] Setup · Open Add Account dialog from header · WebSectionHeader trailing FilledButton.icon "Add Account"
- [ ] Setup · See loading spinner while accounts load · _SetupBody isLoading
- [ ] Setup · See "No accounts yet" empty state · _EmptyState card
- [ ] Setup · Add account from empty state · _EmptyState FilledButton.icon "Add Account"

### KPI row
- [ ] Setup · View Accounts count tile with "{n} liquid" · _SetupKpiRow WebStatTile
- [ ] Setup · View Liquid Cash tile · _SetupKpiRow WebStatTile
- [ ] Setup · View Savings & Goals tile · _SetupKpiRow WebStatTile
- [ ] Setup · View Credit Available tile · _SetupKpiRow WebStatTile
- [ ] Setup · KPI tiles reflow 4/2/1-up · _SetupKpiRow LayoutBuilder

### Accounts table
- [ ] Setup · View accounts grouped Liquid / Savings & Goals / Credit / Custodian · _AccountsTableCard, _AccountGroupHeader
- [ ] Setup · See sub-accounts indented under their parent · _AccountTableRow indented
- [ ] Setup · View account badge icon and name · _AccountTableRow ACCOUNT cell, AccountBadge
- [ ] Setup · See goal progress bar under goal name · _AccountTableRow ACCOUNT cell WebProgressBar
- [ ] Setup · See "Credit" badge on liability accounts · _AccountTableRow ACCOUNT cell WebBadge
- [ ] Setup · Change account type inline via dropdown · _AccountTableRow TYPE cell, _TypeDropdown
- [ ] Setup · Inline type options: top-level asset types only · _TypeDropdown (_kTopLevelSwitchable)
- [ ] Setup · Inline type options for sub-accounts: savings/goal/time deposit · _TypeDropdown (_kSubSwitchable)
- [ ] Setup · Credit accounts show static type label (not editable) · _AccountTableRow TYPE cell
- [ ] Setup · See "Set a goal target in Edit…" toast after switching to Goal · _TypeDropdown _changeType AppToast
- [ ] Setup · Row moves to its new section after type change · _AccountsTableCard regroup
- [ ] Setup · View balance (red for credit) · _AccountTableRow BALANCE cell
- [ ] Setup · See "of {target}" under goal balance · _AccountTableRow BALANCE cell
- [ ] Setup · View credit limit (v2: merged "Credit / target" column; blank, not "—", on liquid rows) · _AccountTableRow CREDIT LIMIT cell
- [ ] Setup · View available credit (v2: merged "Credit / target" column) · _AccountTableRow AVAILABLE cell
- [ ] Setup · Add savings pocket / goal under a liquid parent · Row actions IconButton ⊕ (tooltip "Add savings pocket / goal"; top-level liquid only)
- [ ] Setup · Edit an account · Row actions IconButton pencil (tooltip "Edit account")
- [ ] Setup · Delete an account · Row actions IconButton trash (tooltip "Delete account")
- [ ] Setup · Confirm account deletion · "Delete Account?" AlertDialog TextButton "Delete" (error colour)
- [ ] Setup · Cancel account deletion · "Delete Account?" TextButton "Cancel"
- [ ] Setup · See error toast when account has sub-accounts · AppToast.error "Remove all sub-accounts first…"
- [ ] Setup · See error toast when account has transactions/bills · AppToast.error "This account has transactions or bills…"
- [ ] Setup · Scroll accounts table horizontally on narrow screens · _AccountsTableCard horizontal scroll (min 820px)

### Categories table
- [ ] Setup · View categories, expense first then income · _CategoriesCard
- [ ] Setup · Rename a category inline · _CategoryTableRow name TextField
- [ ] Setup · Press Enter to commit category rename · _CategoryTableRow onSubmitted
- [ ] Setup · Blur commits category rename · _CategoryTableRow focus listener
- [ ] Setup · Empty rename reverts to old name · _CategoryTableRow _commit
- [ ] Setup · Change category icon via picker · _CategoryTableRow WebCategoryIconPreview (tooltip "Choose category icon")
- [ ] Setup · Change category type Expense/Income · _CategoryTableRow _CategoryTypeDropdown
- [ ] Setup · Click swatch to cycle category colour · _CategoryTableRow _ColorSwatch (tooltip "Click to change color")
- [ ] Setup · Toggle exclude from income/expense totals · _CategoryTableRow Switch (tooltip "Exclude from income/expense totals")
- [ ] Setup · Delete a category · _CategoryTableRow IconButton trash (tooltip "Delete category")
- [ ] Setup · Confirm category deletion · "Delete category?" AlertDialog TextButton "Delete" (error colour)
- [ ] Setup · Cancel category deletion · "Delete category?" TextButton "Cancel"
- [ ] Setup · See error toast when category has transactions · AppToast.error "This category has transactions linked…"
- [ ] Setup · Type new category name · Add row TextField (hint "Add a category…")
- [ ] Setup · Add-row icon preview tracks typed name · Add row WebCategoryIconPreview
- [ ] Setup · Pick icon for new category · Add row WebCategoryIconPreview → icon picker
- [ ] Setup · Choose type for new category · Add row _CategoryTypeDropdown
- [ ] Setup · Click swatch to cycle new category colour · Add row _ColorSwatch
- [ ] Setup · Press Enter to add the category · Add row TextField onSubmitted
- [ ] Setup · Click check button to add category · Add row IconButton ✓ (tooltip "Add category")
- [ ] Setup · See spinner while category is being added · Add row _submitting indicator
- [ ] Setup · Add row resets name/icon and advances colour after add · _CategoriesCard _add
- [ ] Setup · Scroll categories table horizontally on narrow screens · _CategoriesCard horizontal scroll (min 480px)

### Category icon picker (opened from Setup)
- [ ] Setup · Pick "Auto" icon · "Choose an icon" dialog _IconChoice "Auto"
- [ ] Setup · Pick a catalog icon by group · "Choose an icon" dialog grouped Wrap
- [ ] Setup · See current icon highlighted · _IconChoice selected state
- [ ] Setup · Cancel icon picker · "Choose an icon" TextButton "Cancel"

### Account form dialog – frame
- [ ] Setup · See "Add Account" or "Edit Account" title · WebAccountFormDialog header
- [ ] Setup · Close dialog via X · Header IconButton close (tooltip "Close"; disabled while saving)
- [ ] Setup · Scroll long form body · Dialog SingleChildScrollView
- [ ] Setup · Cancel the form · Footer TextButton "Cancel"
- [ ] Setup · Save new account · Footer FilledButton "Add Account"
- [ ] Setup · Save edited account · Footer FilledButton "Save"
- [ ] Setup · See spinner in save button while saving · Footer FilledButton _isSubmitting
- [ ] Setup · See error toast if save fails · AppToast.error "Could not save account: …"
- [ ] Setup · Delete account from edit form · Footer TextButton.icon "Delete" (edit only, error colour)
- [ ] Setup · Confirm/cancel delete from edit form · "Delete Account?" AlertDialog Delete/Cancel
- [ ] Setup · See delete error toasts from form · AppToast.error (sub-accounts / transactions)

### Account form dialog – common fields
- [ ] Setup · Enter account name (autofocus on add) · TextFormField "Account Name"
- [ ] Setup · See "Enter account name" validation · Account Name validator
- [ ] Setup · Choose account category · DropdownButtonFormField "Category"
- [ ] Setup · Category list limited to savings/goal/time deposit for sub-accounts · Category dropdown (_subAccountCategories)
- [ ] Setup · Enter opening balance / amount owed · TextFormField balance (label varies by category, ₱ prefix)
- [ ] Setup · See balance helper hint text · Balance field helperText
- [ ] Setup · Press Enter in balance field to submit form · Balance onFieldSubmitted
- [ ] Setup · See invalid number / negative balance validation · Balance validator
- [ ] Setup · Open icon or monogram picker · "Icon" InkWell row "Tap to choose an icon or monogram"
- [ ] Setup · Preview badge with chosen icon/colour · Icon row AccountBadge
- [ ] Setup · Pick account colour from swatches · _ColorSwatchPicker (8 swatches, check on selected)

### Account form dialog – conditional fields
- [ ] Setup · Enter goal target (Goal only) · TextFormField "Goal Target"
- [ ] Setup · See "Enter a goal target" validation · Goal Target validator
- [ ] Setup · Pick maturity date (Time deposit only) · _MaturityDateField → showDatePicker
- [ ] Setup · See "Pick a date" placeholder for maturity · _MaturityDateField
- [ ] Setup · Link custodian funds to a liquid account · DropdownButtonFormField "Stored in account (optional)"
- [ ] Setup · Choose "— Not linked —" for custodian · Custodian dropdown null item

### Account form dialog – credit details (credit card / line / BNPL)
- [ ] Setup · Pick card brand preset to prefill finance rate · DropdownButtonFormField "Card type (optional)"
- [ ] Setup · Choose "— Manual —" brand · Card type dropdown null item
- [ ] Setup · Enter credit limit · TextFormField "Credit Limit"
- [ ] Setup · See credit limit number validation · Credit Limit validator
- [ ] Setup · Choose due mode Day of month / Days after statement · _FullWidthSegments "Payment due"
- [ ] Setup · Choose statement day (1–28) · _DayNumberDropdown "Statement day"
- [ ] Setup · Choose due day of month (1–28) · _DayNumberDropdown "Due day"
- [ ] Setup · Choose due days after statement · _DayNumberDropdown "Due after"
- [ ] Setup · See helper text for days-after mode · Credit details help text
- [ ] Setup · Choose minimum rule % of balance / Fixed / Pay in full · _FullWidthSegments "Minimum payment"
- [ ] Setup · Enter fixed minimum amount (Fixed only) · TextFormField "Minimum amount"
- [ ] Setup · See "Enter an amount above ₱0" validation · Minimum amount validator
- [ ] Setup · Enter monthly finance rate (% / mo) · TextFormField "Monthly finance rate"
- [ ] Setup · See finance rate number validation · Finance rate validator

## Goals (mobile `GoalsSavingsScreen` mounted in the desktop shell today; Phase 9 builds a web page)

- [ ] Goals · Add goal (floating button today; header button in v2) · GoalsSavingsScreen FAB
- [ ] Goals · Goal cards: name, progress, saved of target, monthly set-aside, "at this pace" date · GoalsSavingsScreen goal list
- [ ] Goals · "Set a monthly amount" on a goal with no set-aside opens the set-aside dialog · GoalsSavingsScreen card action
- [ ] Goals · Mark a funded goal as spent (goal lifecycle) · GoalsSavingsScreen card menu (see docs/goal_lifecycle_spec.md)
- [ ] Goals · Start again (reset balance to zero, keep target) with confirm · GoalsSavingsScreen "Start again…"
- [ ] Goals · Savings & investments table (balances not tied to a target) · GoalsSavingsScreen savings section
- [ ] Goals · Funding-model note (goals are Savings rows funded via set-asides) · GoalsSavingsScreen footer note
- [ ] Goals · Link to the Savings rows in Budget / Manage in Setup · GoalsSavingsScreen links

## More (narrow layout only — unchanged by Plan 063 except the added Setup entry)

- [ ] More (narrow) · "More" tab in the narrow bottom tabs · `TreasuryModuleTab` "More" (`extraTabs`)
- [ ] More (narrow) · Page title "MORE" · `WebMorePage` AppBar
- [ ] More (narrow) · Open Nudgy as a bottom sheet · Nudgy section, FilledButton.tonalIcon "Open Nudgy"
- [ ] More (narrow) · Nudgy sheet can be dragged between 40% and 95% height · `AiChatSheet` DraggableScrollableSheet
- [ ] More (narrow) · Nudgy sheet has the same chat actions as the desktop panel · `AiChatBody` with drag handle and entry label
- [ ] More (narrow) · Toggle dark mode · Appearance section, `SwitchListTile` "Dark mode"
- [ ] More (narrow) · Signed-in email shown · Account section, email Row
- [ ] More (narrow) · Sign out · Account section, OutlinedButton.icon "Sign out"
- [ ] More (narrow) · Setup & Accounts reachable from More (ADDED by Plan 063 Phase 1; today Setup is unreachable below 840) · `WebMorePage` (new entry)

## Shared kit

### Searchable dropdown (web_searchable_dropdown.dart)
- [ ] Shared · Dropdown · Click field to open; click again to close · WebSearchableDropdown InkWell
- [ ] Shared · Dropdown · Field shows selected label with color dot, or hint · _buildField
- [ ] Shared · Dropdown · Search box focused automatically when opened · _buildSearchField autofocus
- [ ] Shared · Dropdown · Type to filter (all words must match, any case) · _filtered
- [ ] Shared · Dropdown · Enter selects the first match · TextField onSubmitted
- [ ] Shared · Dropdown · Esc closes the dropdown · FocusNode onKeyEvent
- [ ] Shared · Dropdown · Click an option to select and close · ListView InkWell
- [ ] Shared · Dropdown · Current choice highlighted with ✓ · _buildList isSelected
- [ ] Shared · Dropdown · "No matches" empty state · _buildList
- [ ] Shared · Dropdown · List scrolls past 320px height · ConstrainedBox maxHeight
- [ ] Shared · Dropdown · Click outside closes it (click still reaches what's under it) · translucent GestureDetector barrier

### WebDataTable (used by History and Bills)
- [ ] Shared · DataTable · Click row to run row action (when enabled) · _BodyRow GestureDetector
- [ ] Shared · DataTable · Hover tint and pointer cursor on clickable rows · _BodyRow MouseRegion
- [ ] Shared · DataTable · Alternate rows shaded (zebra) · _BodyRow zebra
- [ ] Shared · DataTable · Section band with title and trailing summary · _SectionBand
- [ ] Shared · DataTable · Empty label (default "No records") · WebDataTable emptyLabel

### WebBatchBar / WebBatchSelectControl (used by Bills)
- [ ] Shared · BatchBar · "Select" button starts selection (disabled if locked/empty) · WebBatchSelectControl TextButton.icon
- [ ] Shared · BatchBar · "N selected" count shown · WebBatchSelectControl / WebBatchBar Text
- [ ] Shared · BatchBar · Select all / Clear all · WebBatchSelectControl TextButton
- [ ] Shared · BatchBar · Cancel selection · WebBatchSelectControl TextButton "Cancel"
- [ ] Shared · BatchBar · Settle "<Pay/Receive/Fund> N" (disabled at 0) · WebBatchBar FilledButton.icon
- [ ] Shared · BatchBar · "Undo N" (disabled at 0) · WebBatchBar OutlinedButton.icon
- [ ] Shared · BatchBar · "Delete N" (red, disabled at 0) · WebBatchBar OutlinedButton.icon
- [ ] Shared · BatchBar · All actions disabled while a batch runs · WebBatchBar enabled flag
- [ ] Shared · BatchBar · Row selection checkbox · WebRowSelectBox Checkbox

### Charts (web_charts.dart)
- [ ] Shared · Charts · Hover line chart point for month + value tooltip · WebLineChart LineTouchTooltipData
- [ ] Shared · Charts · Hover multi-line chart for per-series value tooltip · WebMultiLineChart LineTouchTooltipData
- [ ] Shared · Charts · Hover bar for series + value tooltip · WebBarPairChart BarTouchTooltipData
- [ ] Shared · Charts · Static legends (multi-line, bar pair); donut legend optional · WebMultiLineChart / WebBarPairChart / WebDonutChart
- [ ] Shared · Charts · "No data" empty state in every chart · WebLineChart / WebMultiLineChart / WebDonutChart

### Month stepper (web_month_stepper.dart — Ledger, Bills, Budget)
- [ ] Shared · Month stepper · Previous month (tooltip "Previous month") · WebMonthStepper IconButton
- [ ] Shared · Month stepper · Next month (tooltip "Next month") · WebMonthStepper IconButton
- [ ] Shared · Month stepper · Month label · WebMonthStepper Text

### Theme and feedback
- [ ] Shared · Every page renders in dark and light mode with theme-aware colors only · buildWebDarkTheme / buildWebLightTheme
- [ ] Shared · Every toast goes through AppToast (success / error / action with Retry or Undo) · AppToast
- [ ] Shared · Every dialog closes on Esc and (where set) on a click outside · showDialog defaults
