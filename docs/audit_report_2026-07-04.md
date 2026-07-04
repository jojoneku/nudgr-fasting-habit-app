# Codebase Audit — 2026-07-04

Multi-agent audit: 5 parallel dimension auditors (security, web-mobile parity, logic, scalability, consistency), adversarial verification of high/med findings, synthesized report.

## Top 10 — Fix First

| Rank | Severity | Dimension | Location | Issue |
|---|---|---|---|---|
| 1 | high | scalability | `lib/services/local_storage_service.dart:1007` | Every save marks ALL transactions dirty, bumping every record's LWW timestamp — any local save makes sync pulls discard all remote edits from other devices (silent multi-device data loss) |
| 2 | high | scalability | `lib/services/sync_queue.dart:76` | 1000-entry queue cap silently evicts dirty marks during full-list save bursts — edits to older rows never reach the cloud and can never be pulled back (permanently stranded) |
| 3 | high | security | `backend/ai-coach/lambda_function.py:94` | Lambda logs the full request event — live replayable Supabase JWT plus health/finance PII persisted to CloudWatch on every invocation |
| 4 | high | parity | `lib/views/treasury/shared/account_setup_view.dart:188` | Mobile edit form drops `parentAccountId`, orphaning sub-account pockets and double-counting their balance in totalAssets/netWorth (silent data corruption; web already fixed) |
| 5 | high | parity | `lib/views/web/pages/bills/web_bills_page.dart:1053` | Web mark-paid uses the liability account itself as payer — every credit-card statement bill throws (uncaught) and can never be paid on web |
| 6 | med | logic | `lib/presenters/activity_presenter.dart:183` | No day-rollover guard: after midnight, today's Health Connect data is persisted under yesterday's key, silently overwriting yesterday's real totals (also synced to cloud) |
| 7 | med | parity | `lib/views/web/pages/ledger/web_ledger_page.dart:348` | Inline amount edit flips transaction type but keeps the old category, creating income rows with expense categories that fall out of all category aggregations |
| 8 | med | logic | `lib/presenters/treasury_dashboard_presenter.dart:182` | totalLiquidCash and netWorth subtract UNLINKED custodian balances that were never in the asset base — both KPIs understated |
| 9 | med | security | `nudgr_data_backup/FlutterSharedPreferences.xml:1` | Real device data dump (activity telemetry, meal logs, test finance records) tracked in a now-public repo |
| 10 | med | logic | `lib/presenters/nutrition_presenter.dart:664` | Weight log appended unsorted — a backdated weigh-in becomes "latest" and corrupts delta/trend and cut/recomp status |

---

## Security

- **high** `backend/ai-coach/lambda_function.py:94` — Lambda logs full request event; Supabase JWT and PII land in CloudWatch. Unconditional `print(json.dumps(event))` on every invocation dumps the Authorization header (live, replayable access token) plus chat messages, base64 food photos, and the finance-classifier prompt with account names/amounts. No debug gate, no redaction.
- **med** `nudgr_data_backup/FlutterSharedPreferences.xml:1` — Real user data dump committed to git in a public repo. Tracked SharedPreferences export contains ~30 days of real activity telemetry, a day of meal logs, and test-flavored finance records. No secrets or identity linkage, but live exposure since the repo went public.
- **med** `web/index.html:46` — Clickjacking protection is ineffective. `frame-ancestors` via `<meta>` is ignored by all browsers per the CSP spec, and `firebase.json` sets only Cache-Control — the hosting-layer CSP/X-Frame-Options the file's own comment mandates was never added, leaving the deployed finance web app framable.
- **low** `lib/services/food_photo_store.dart:51` — Path traversal via cloud-synced `photoThumbnailPath` in delete()/absolutePath(); relativePath is joined to the documents dir with no `..`/absolute-path validation and round-trips unvalidated through Supabase. (unverified)
- **low** `lib/main.dart:8` — Mobile release builds never silence debugPrint; userId and raw HTTP response bodies reach logcat (web entrypoint has the guard, mobile does not; sync_service's "stripped in release" comment is wrong). (unverified)
- **low** `lib/services/auth_service.dart:39` — Supabase session (access + refresh token) persisted to plaintext SharedPreferences via SDK default, while a less-sensitive HF token uses flutter_secure_storage. (unverified)
- **low** `backend/ai-coach/lambda_function.py:88` — Bedrock daily-cap rate limiter fails open on any Supabase/transport error or missing env, silently removing the only guard against unbounded Bedrock billing. (unverified)

> The security auditor also flagged the ledger daily-net badge (`ledger_view.dart:1313`); merged into Consistency below.

## Parity

- **high** `lib/views/treasury/shared/account_setup_view.dart:188` — Mobile edit form orphans sub-accounts, double-counting their balance in net worth. `_submit` saves `parentAccountId: widget.parentAccountId` (null when editing a pocket from the dashboard Goals section), detaching it from its parent while the parent's balance still includes it. Web fixed exactly this (`_effectiveParentId`, Plan 052 C1); mobile was not. Trigger: tap a pocket, Save unchanged.
- **high** `lib/views/web/pages/bills/web_bills_page.dart:1053` — Web mark-paid uses the liability account as payer, so credit-card statement bills throw and cannot be paid. Auto-generated statements carry `accountId` = the credit account; `markBillPaid` throws ArgumentError for that combination, and the Future is discarded — bill stays unpaid with zero feedback. Mobile avoids this via `payerAccountsFor(bill)`.
- **med** `lib/views/web/pages/ledger/web_ledger_page.dart:348` — Inline amount edit flips type but keeps the old category, creating expense-category income rows impossible on mobile (mobile and the web modal both clear category on type change). The mismatched row orphans out of both income- and spend-category aggregations.
- **med** `lib/views/web/pages/dashboard/web_dashboard_page.dart:493` — Web Budget Health total includes savings budgets; mobile deliberately excludes them. Same headline "% of ₱X used" differs across surfaces for the same month, and the web card mislabels an on-track savings goal as "Over".
- **med** `lib/views/web/pages/ledger/web_ledger_page.dart:409` — Web draft add-row silently stamps the first expense category and first liquid account when none was picked (no validation error), misattributing spend; mobile and the web modal dialog both validate explicit selection.
- **low** `lib/views/web/pages/history/web_history_page.dart:153` — History averages computed via folds in `build()` including the live month, while presenter getters (closed-months-only) sit unused/dead; a Rule-1 cleanup — hoist into the presenter and reconcile/delete the dead getters. *(Also flagged by scalability: line 34's `currentMonthSummary` runs a full transaction scan per rebuild — merged here.)*
- **low** `lib/views/web/pages/ledger/web_ledger_page.dart:498` — Web category filter offers the reserved system "Transfer" category; mobile deliberately excludes it. (unverified)
- **low** `lib/views/web/pages/ledger/web_ledger_page.dart:131` — "Owed to you" (outstanding reimbursables) filter exists in the presenter and mobile UI but is missing from web. (unverified)
- **low** `lib/views/web/pages/bills/web_bills_page.dart:1111` — Web mark-paid/mark-received always posts the full amount on today's date; partial and backdated payments are mobile-only. (unverified)
- **low** `lib/views/web/pages/bills/web_bills_page.dart:1577` — Web set-aside funding silently uses the first active liquid account with no picker; mobile offers an account dropdown. (unverified)
- **low** `lib/views/web/pages/bills/web_bills_page.dart:169` — Web add-bill dialog omits the recurring toggle and payment note (documented TODO), so bills created on web never auto-copy to the next month. (unverified)
- **low** `lib/views/web/pages/dashboard/web_dashboard_page.dart:482` — Budget "Watch" threshold is 0.85 on the web dashboard but 0.75 on both the mobile dashboard and web budget page. (unverified)
- **low** `lib/views/web/pages/budget/web_budget_page.dart:83` — Web budget page rebuilds its own row model in the view instead of using `BudgetPresenter.budgetRows`, which exists precisely so the view stays math-free; drift risk. (unverified)
- **low** `lib/views/web/pages/bills/web_bills_page.dart:76` — `receiveTotal` folded in build() duplicating `presenter.totalReceivablesPending`. (unverified)
- **low** `lib/views/web/pages/dashboard/web_dashboard_page.dart:718` — Daily Spending 7-day total (and Where-Money-Goes / Cash Flow percent) folded in build() with no presenter getter. (unverified)
- **low** `lib/views/web/pages/history/web_history_page.dart:500` — Category breakdown parses `colorHex` raw instead of the brightness-aware `resolveSliceColor` used everywhere else; low-contrast swatches in one theme mode. (unverified)
- **low** `lib/views/web/treasury_web_app.dart:382` — Grocery cart feature absent from the desktop web shell navigation despite the presenter being constructed and passed down. (unverified)
- **low** `lib/views/web/pages/setup/web_setup_page.dart:517` — Web setup allows flipping an existing category between Expense and Income with no guard even when transactions reference it; mobile never offers a type edit. (unverified)

> Parity's daily-net badge finding (`ledger_view.dart:1313`, reimbursable angle), savings-definition mismatch (`treasury_dashboard_presenter.dart:259`), and held-funds fold (`treasury_dashboard_view.dart:425`) are merged into Consistency below.

## Logic

- **med** `lib/presenters/activity_presenter.dart:183` — No day-rollover guard on `_todayLog`: an overnight resume writes today's Health Connect data under yesterday's key, silently overwriting yesterday's real totals (also cloud-synced); `backfillHistory` never repairs. NutritionPresenter has `_ensureTodayLogFresh` for exactly this; ActivityPresenter has no equivalent.
- **med** `lib/presenters/treasury_dashboard_presenter.dart:182` — totalLiquidCash and netWorth subtract UNLINKED custodian balances that are in neither `liquidAccounts` nor `totalAssets`, understating both KPIs; `heldAmountByAccountId` counts only linked custodians, so dashboard rows disagree with the KPI.
- **med** `lib/presenters/nutrition_presenter.dart:664` — Weight log appended unsorted; a backdated entry becomes `weightLog.last` ("latest"), flipping delta/trend and potentially the cut/recomp status. The parallel `logMeasurement` path sorts; this one doesn't.
- **med** `lib/presenters/ledger_presenter.dart:328` — `_accountBalanceByTxnId` reconstructs a parent's balance history ignoring sub-account transactions that also moved the parent's live balance, so every "balance after txn" value in the web spreadsheet view is wrong for any parent with pocket activity.
- **med** `lib/presenters/quest_presenter.dart:198` — Toggle-off of a completed quest never decrements `streakCount`, so complete→untick→complete inflates the streak by 1 per cycle, farmable toward the 21-day linkedStat award, milestones, and streak freezes (XP itself is deduped).
- **med** `lib/presenters/quest_presenter.dart:215` — `_xpAwardedToday` is keyed to `DateTime.now()`, so a grace completion of yesterday's quest stamps today's date and blocks XP for today's genuine completion (UI can still show XP that was never credited).
- **med** `lib/presenters/fasting_presenter.dart:219` — `currentStreak`/`longestStreak` use `diff <= 1`, so two successful fasts ending on the same calendar day count as two streak days; streaks should count distinct days.
- **med** `lib/presenters/fasting_presenter.dart:563` — `updateStartTime` shows the persistent fasting timer notification (id 999) then immediately cancels it; the ongoing chronometer disappears after a mid-fast start-time edit. `updateEatingStartTime` has the same bug for id 998.
- **med** `lib/presenters/fasting_presenter.dart:519` — `skipEatingWindow` clears eating state but never calls `cancelEatingNotifications`: the un-dismissable eating-timer notification lingers and the window-over alarm fires for a skipped window; the ticker also keeps running.
- **med** `lib/presenters/bills_receivables_presenter.dart:554` — All-bills-paid +50 XP has no persisted once-per-month guard and is farmable (unpay/re-pay, or add one more bill and pay it). BudgetPresenter fixed this exact farming class with a persisted per-month key; this path has no equivalent.
- **med** `lib/presenters/installment_presenter.dart:178` — Installment completion (+50) and all-due-paid (+20) XP re-awardable via markUnpaid/markPaid cycles (+70 per cycle); no award ledger and markUnpaid deducts nothing.
- **med** `lib/presenters/activity_presenter.dart:359` — Activity streak is never reset on a missed day, so "+1 AGI every 5 consecutive days" fires on cumulative days (e.g. 5 non-consecutive Mondays). The correct reset pattern exists in NutritionPresenter but was never applied here.
- **low** `lib/presenters/quest_presenter.dart:162` — Missed-quest penalty runs in `_init` before the 00:30 grace window can be used: HP damage + streak reset are applied and never refunded when the user then grace-completes. Latent — no view currently wires up the grace feature.
- **low** `lib/presenters/bills_receivables_presenter.dart:149` — `billStatus` clamps dueDay to 28 while the model/forms allow 1–31, mis-flagging late-month bills as overdue early; currently dead code (no call sites), so latent.
- **low** `lib/presenters/treasury_history_presenter.dart:347` — `closePreviousMonthIfNeeded` snapshots CURRENT live balances as last month's endingCash; opening the app days into a new month bakes current-month activity into the "month-end" snapshot. (unverified)
- **low** `lib/presenters/nutrition_presenter.dart:1891` — `_combineEntriesAsOneDish` sourceRank map omits `cloudAiFallback`, ranking the documented worst source as best; combined dishes never show the degraded-source badge. (unverified)
- **low** `lib/presenters/fasting_presenter.dart:364` — `stopFast` returns pre-STR-bonus XP, so the completion modal understates the real award as STR grows. (unverified)
- **low** `lib/presenters/installment_presenter.dart:168` — `markPaid` stamps month = `_selectedMonth` but date = now, so browsing a different month creates rows whose month bucket disagrees with their date. (unverified)
- **low** `lib/presenters/update_presenter.dart:7` — Takes concrete `LocalStorageService` instead of the `StorageService` interface (Rule 2), and the field is unused. (unverified)

## Scalability

- **high** `lib/services/local_storage_service.dart:1007` — `saveTransactions` marks EVERY transaction dirty per save (LedgerPresenter always passes the full list): the whole ledger is re-queued and re-uploaded per single edit, and — worse — `markDirty` bumps ALL records' local LWW timestamps to now, so a pull after any local save discards every remote edit made on another device. Fix: diff old vs new (id cache already exists) and mark only changed rows.
- **high** `lib/services/sync_queue.dart:76` — 1000-entry cap silently evicts marks when a full-list save overflows it: at >1000 finance records, edits to older rows are evicted before push, and since their timestamps were already bumped, pull LWW refuses the remote copy too — the edit permanently never syncs and is lost on sign-out. Cap is global, so a finance burst evicts non-finance marks as well.
- **med** `lib/services/sync_queue.dart:69` — `markDirty` does a full-queue `removeWhere` per call; one edit at 5k rows costs ~5M synchronous main-isolate comparisons (plus `removeEntries` repeats the pattern post-push). Fix: back the queue with a Map keyed by `domain::key`.
- **med** `lib/services/local_storage_service.dart:1014` — Every transaction mutation re-encodes the full transaction list to one SharedPreferences string on the UI isolate (~1–2 MB jsonEncode at 5k rows per inline edit); optimistic notify hides only the first frame. Fix: chunked/keyed storage or encode in an isolate.
- **med** `lib/presenters/bills_receivables_presenter.dart:57` — `_notifyDependents` awaits `dashboard.load()` + `budget.load()` after every bill/receivable mutation (13 call sites), each fully re-decoding the transaction blob — two extra full JSON decodes per "mark paid" tap. Fix: mirror in-memory state via the existing `_syncFromLedger` pattern.
- **med** `lib/presenters/treasury_dashboard_presenter.dart:850` — Four presenters (ledger, dashboard, history, budget) each independently jsonDecode the full transaction blob at boot — 4 redundant parses of identical data despite LedgerPresenter being the documented source of truth.
- **med** `lib/presenters/treasury_dashboard_presenter.dart:592` — `_lastNDaysSpending` scans all transactions once per day, and the analytics card reads three getters that each rebuild the series — ~21 full-list scans per card rebuild (web dashboard repeats a 7-scan variant). Fix: single-pass bucket + one cached record.
- **low** `lib/services/sync_queue.dart:97` — Per-record timestamp map grows unboundedly (deleted-record keys never pruned) and is fully re-encoded to prefs per flush; slow-accumulating overhead. Note: naive pruning of tombstone timestamps would break tombstone LWW suppression.
- **low** `lib/presenters/budget_presenter.dart:151` — `totalSpent`/`budgetRows` are O(budgets × all-transactions) getters recomputed per access with `_budgetsForMonth` re-materialized per call; genuine growth liability, sub-ms at current scale. Fix: one-pass categoryId→spent map cached per notify.
- **low** `lib/presenters/budget_presenter.dart:45` — `_checkBudgetWarnings` runs full O(budgets × transactions) scans on EVERY ledger notify including pure UI filter changes (setMonth/setAccount). Fix: gate on actual data-identity change.
- **low** `lib/presenters/treasury_dashboard_presenter.dart:509` — `forecastedNetBalance` chain re-scans all transactions per budget with no memoization, and both mobile and web dashboards read the getter twice per build.
- **low** `lib/views/web/pages/ledger/web_ledger_page.dart:685` — Web ledger grid uses non-builder `ListView(children:)` plus uncached O(m log m) filter/sort per rebuild; known deferred virtualization item (search is already debounced, so cost is resize/selection-driven, not per-keystroke). Fixed row extent makes `ListView.builder` + `itemExtent` a drop-in.
- **low** `lib/presenters/ledger_presenter.dart:431` — `isOutstandingReimbursable` fallback rebuilds the settled-ids set per predicate call inside loops — O(n²) worst case; hoist the set. (unverified)
- **low** `lib/presenters/ledger_presenter.dart:130` — `reimbursementReceivableIds` full-list scan independently recomputed by filteredMonthInflow, dailyInflowMap, and tableInflow in the same build; cache alongside `_rowsForMonthCache`. (unverified)
- **low** `lib/presenters/treasury_history_presenter.dart:145` — averageSavingsContribution/cumulative/monthMatrix re-filter all transactions per month, O(months × n); currently dead code — group by month in one pass or delete. (unverified)
- **low** `lib/services/local_storage_service.dart:1041` — Six finance save methods do a full load-and-decode just to diff ids on every save; extend the in-memory id-cache pattern transactions/accounts already use. (unverified)

## Consistency

- **med** `lib/views/treasury/ledger/ledger_view.dart:1313` — Daily-net badge is a view-side fold with neither the transfer-exclusion nor the reimbursable-exclusion policy. `_DateGroup._dailyNet` folds inflow−outflow in the widget (Rule 1; no presenter getter exists): under an account filter only one transfer leg is present, so moving money between own accounts shows as fake daily income/spend (PR #291 policy violation), and reimbursable outflows move the badge while the Income/Expenses/Net chips directly above exclude them — two exclusion rules on one screen. Its `TransactionType.transfer` arm is dead code (legs are stored as outflow/inflow). *(Merged: also reported by security and parity — same file/root cause.)*
- **med** `lib/presenters/treasury_dashboard_presenter.dart:259` — Two conflicting definitions of "savings contributions": dashboard sums ALL inflow/outflow on `isLocked` accounts (includes investment and direct income), while history counts only transfer legs into `isSavingsPocket` accounts (explicitly excludes investment). Same-labeled figures disagree across pages for the same month; a third "savings rate" definition (netSavings/totalInflow) exists in history. *(Merged: also reported by parity.)*
- **med** `lib/presenters/budget_presenter.dart:302` — Savings net-contribution loop duplicated in TreasuryDashboardPresenter._budgetSpentFor (and a third copy in monthSavingsContributions); the comment admits consistency is maintained by hand — a fix in one silently diverges the financial totals the three surfaces are supposed to reconcile. Extract a shared helper.
- **med** `lib/models/fasting_log.dart:2` — FastingLog is fully mutable (only model in lib/models/ with zero final fields, no copyWith) and overrides ==/hashCode over mutable fields; `timer_tab.dart:205` exploits it by mutating `log.note` directly from the View layer.
- **med** `lib/views/tabs/timer_tab.dart:200` — Streak/success RPG math re-derived in the view for FastCompletionModal, and it actually diverges from the presenter: ticker vs wall-clock success at the goal boundary, stale streak shown on failed fasts, wrong "+1" after multi-day gaps. Rule 3 violation; correct values are available from the presenter post-stopFast.
- **med** `lib/views/quests/quest_detail_view.dart:268` — `quest.streakCount % 21` hardcodes the presenter-private `_statProgressThreshold` in build() while the same widget already calls `statProgressFor`; duplicated magic number with silent-divergence risk.
- **med** `lib/views/nutrition/nutrition_history_screen.dart:1041` — Weekly macro averages computed via three fold-and-divide getters consumed in build(); belongs in NutritionPresenter, which already owns adjacent stats (logStreak, sevenDayAvgCalories).
- **low** `lib/presenters/budget_presenter.dart:290` — Spending predicate ("outflow && no transferGroupId && !reimbursable") inlined in sectionSpent/spentFor instead of the shared `isSpendingOutflow` helper the other presenters use (and this file already imports); pure drift risk today.
- **low** `lib/views/web/pages/ledger/web_ledger_page.dart:3133` — Transfer-leg From/To reconstruction: identical O(n) leg-pairing loops in two views, redundant with `TransactionRecord.transferFromAccountId/transferDestinationAccountId` model getters the same web file already uses elsewhere.
- **low** `lib/presenters/fasting_presenter.dart:15` — Six public mutable fields (including a raw mutable `history` list) break the private-field+getter pattern every other presenter follows; no external mutation exists today, so latent.
- **low** `lib/presenters/quest_presenter.dart:158` — Unguarded `notifyListeners()` after four awaits while `reload()` in the same class guards; quest/fasting/sync presenters hand-roll `_disposed` despite the SafeNotifier mixin used by the other eight. Debug-assert-only impact.
- **low** `lib/views/stats_view.dart:197` — HP/XP progress ratios computed in build() and duplicated in stats_hub_card with a divide-guard this copy lacks (guard is unreachable in practice); should be StatsPresenter getters.
- **low** `lib/views/treasury/dashboard/treasury_dashboard_view.dart:425` — `_HeldFundsCard` re-folds custodian balances in build(), an exact duplicate of `presenter.totalHeldForOthers`; no divergence possible today, cleanup only. *(Merged: also reported by parity.)*
- **low** `lib/presenters/quest_presenter.dart:497` — Canonical `yyyy-MM-dd` day key reimplemented ~26 times across two idioms (`toIso8601String().split('T')[0]` vs `DateFormat('yyyy-MM-dd')`); outputs are identical so no failure exists, but a shared `dayKey()` in utils/date_utils.dart is overdue since the key joins storage, widgets, and sync.
- **low** `lib/presenters/fasting_presenter.dart:109` — Silent `catch (_) {}` beside debugPrint-logged catches for the same notification failures in one file — two error policies. (unverified)
- **low** `lib/views/treasury/ledger/ledger_view.dart:55` — User feedback split between raw ScaffoldMessenger SnackBars (17 files) and the AppToast design-system overlay (12 files). (unverified)
- **low** `lib/presenters/ledger_presenter.dart:114` — accounts/categories returned as internal mutable lists while allTransactions is wrapped unmodifiable — inconsistent within one class. (unverified)
- **low** `lib/presenters/stats_presenter.dart:11` — Public mutable `showLevelUpDialog` beside the private-field+getter pattern; mutation without notify is possible. (unverified)
- **low** `lib/presenters/ledger_presenter.dart:30` — Two presenter init lifecycles: constructor-fired unawaited load() (7 presenters) vs external init()/load() (2), with constructor futures unobservable by callers. (unverified)
- **low** `lib/services/sync_queue.dart:33` — Four services persist state via raw `SharedPreferences.getInstance()` with private key strings, bypassing the StorageService abstraction and its test seam. (unverified)
- **low** `lib/views/tabs/quests_tab.dart:2` — Dead deprecated re-export shim with zero importers. (unverified)
- **low** `lib/views/stats_view.dart:1` — Four naming conventions for a routed screen (_screen/_view/_tab/_page) across surfaces. (unverified)
- **low** `lib/presenters/ledger_presenter.dart:1125` — Chat summary formats pesos with `toStringAsFixed(0)` instead of the imported `formatPeso` used everywhere else. (unverified)
- **low** `lib/views/web/pages/history/web_history_page.dart:622` — Local `_pct()` re-implements the already-imported `formatPercent`; ~15 more sites hand-roll the same expression. (unverified)
- **low** `lib/presenters/budget_presenter.dart:317` — try/firstWhere/catch used as firstOrNull in some files vs `.firstOrNull` in others — exceptions as control flow for the identical lookup. (unverified)

## Summary

**Counts (after dedupe):**

| Dimension | High | Med | Low | Total (unverified) |
|---|---|---|---|---|
| Security | 1 | 2 | 4 | 7 (4) |
| Parity | 2 | 3 | 13 | 18 (12) |
| Logic | 0 | 12 | 7 | 19 (5) |
| Scalability | 2 | 5 | 9 | 16 (4) |
| Consistency | 0 | 7 | 18 | 25 (11) |
| **Total** | **5** | **29** | **51** | **85 (36)** |

**Dominant themes:**

1. **The sync pipeline is the single biggest risk.** The full-list `saveTransactions` markDirty pattern is one root cause with three consequences: LWW timestamp clobbering that silently discards other devices' edits, queue-cap eviction that permanently strands edits at >1000 records, and O(n)–O(n²) main-isolate bursts per mutation. One fix (diff-based dirty marking + Map-backed queue) addresses ranks 1–2 and most of the scalability meds.

2. **Aggregation logic keeps leaking into views and getting duplicated across presenters.** Roughly a third of all findings are Rule-1/Rule-3 violations or hand-mirrored math (daily-net badge, savings contributions ×3 copies, budget health, streak math in timer_tab). Every user-visible numeric inconsistency found (transfer legs counted as income, savings figures disagreeing across pages, differing budget thresholds) traces to a missing shared presenter getter or helper.

3. **The web companion lags mobile on validation and guards.** Both parity highs plus the inline-edit and draft-row meds are cases where mobile has an explicit guard (payer filtering, parent-id preservation, category clearing, required selection) that web either never got or — in the mobile sub-account case — got fixed on web first and never back-ported. Cross-surface fixes should land as paired changes.

Also worth scheduling despite lower severity: the RPG XP economy is farmable through four independent unguarded paths (quest toggle, bills, installments, activity streak) — one persisted award-ledger pattern (already proven in BudgetPresenter) fixes all four.
