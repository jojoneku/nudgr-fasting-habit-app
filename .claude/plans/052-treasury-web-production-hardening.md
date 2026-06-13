# Plan 052 — Treasury Web Production Hardening

Make the Flutter **web** Treasury companion production-ready. The redesign
(Plans 042/050/051) landed the desktop sidebar + redesigned pages; this plan
closes the gap between "looks built" and "ships safely and feels fast." It is a
full audit of all six web pages, the shared web widget kit, the charts, and the
web attack surface, with fixes grouped into reviewable commits.

Scope: `lib/views/web/**`, `lib/utils/category_colors.dart`, the web entrypoint
(`lib/main_web.dart`), `lib/services/auth_service.dart`, `web/index.html`,
`web/manifest.json`, and the presenter getters the web pages read.

Out of scope: mobile views, the Supabase backend/migrations (RLS is verified
operationally, see G1), the on-device AI path (web has none).

---

## Findings (audited 2026-06-13)

Severity: **C**ritical · **H**igh · **M**edium · **L**ow.

### Security

| ID | Sev | Finding | File |
|----|-----|---------|------|
| S1 | H | `.env` ships as a world-readable web asset (`assets/.env`). Safe **today** (only Supabase URL/anon key + Google client id + redirect — all public-by-design), but any future secret added there is instantly public. | `pubspec.yaml`, `lib/main_web.dart` |
| S2 | H | Authorization rests entirely on Supabase **RLS**; client-side `.eq('user_id', …)` is not a control. Must be verified enabled+forced on all finance tables. | `lib/services/sync_service.dart` |
| S3 | M | No Content-Security-Policy / security headers on the web shell. | `web/index.html` |
| S4 | M | `debugPrint` is **not** stripped in release → userId + record UUIDs + raw Supabase error payloads reach the browser console. | `sync_service.dart`, `treasury_web_app.dart` |
| S5 | M | Supabase session token + full ledger sit in plaintext `localStorage` (accepted-risk for a single-user app; document it). | `auth_service.dart`, `local_storage_service.dart` |
| S6 | L | Missing-env checks are `assert`s (stripped in release) → a bad deploy inits Supabase with empty strings and fails opaquely. | `auth_service.dart` |
| S7 | L | Local data is retained after sign-out when the pre-wipe flush fails, with no user notice (shared-machine concern). | `treasury_web_app.dart` |

### Correctness

| ID | Sev | Finding | File:line |
|----|-----|---------|-----------|
| C1 | C | Editing a **sub-account** orphans it: `_submit` writes `parentAccountId: widget.parentAccountId`, but the setup page opens edit without passing it → saved as `null`, detaching the pocket from its parent. Same root bug feeds the wrong category list. | `web_account_form_dialog.dart:233`, `web_setup_page.dart:53` |
| C2 | H | Bills "Outstanding" tile shows a **duplicate** of "Due This Month" (`outstandingTotal = totalBillsPending`) and ignores the intended bills+expenses getter. | `web_bills_page.dart:75` |
| C3 | H | Inline-edit cell state keyed on **value** (`ValueKey('desc_${id}_${desc}')`) → every commit disposes+recreates the controller/FocusNode, breaking Tab/Enter flow and dropping focus. | `web_ledger_page.dart:1859,1887,1896` |
| C4 | H | Stale-record race: inline edits `copyWith` the `t` captured at build; two fast edits to one row commit the second from the pre-first record, reverting edit #1. | `web_ledger_page.dart:246-273` |
| C5 | M | Edit silently rewrites `icon: _category.name`, discarding `existing.icon`. | `web_account_form_dialog.dart:236` |
| C6 | M | Numeric fields (balance, credit limit, finance rate, bill amount) accept garbage (`1.2.3`) silently coerced to 0; no validators. | `web_account_form_dialog.dart`, `web_bills_page.dart` |
| C7 | M | Save failures are invisible (`try/finally` with no `catch`) — dialog just sits with a reset spinner. | `web_account_form_dialog.dart:252-261`, `web_bills_page.dart:195` |
| C8 | M | Bulk delete fires N unawaited `deleteTransactionOrGroup` calls, each doing a full-list write — redundant writes, no failure handling, no ordering guarantee. | `web_ledger_page.dart:283-285` |
| C9 | L | `updateTransaction`/`deleteTransaction` `firstWhere` throws if the id vanished (reachable via C4/C8). | `ledger_presenter.dart:425,436` |
| C10 | L | Custodian edit can dangle the linked-account dropdown (`initialValue` absent from items → debug assert). | `web_account_form_dialog.dart:474-501` |
| C11 | L | `_AddRow._add` clears controllers after awaits with no `mounted` guard. | `web_budget_page.dart:879-881` |
| C12 | L | Dead boolean clause in `sendChatInput` (`a && b || a` collapses to `a`). | `ledger_presenter.dart:526` |

### Performance

| ID | Sev | Finding | File:line |
|----|-----|---------|-----------|
| P1 | H | `ledgerSpreadsheetRows` (sorts **all history** per account to reconstruct balances) is recomputed on **every page build, including every search keystroke**. No caching. | `ledger_presenter.dart:266`, `web_ledger_page.dart:356` |
| P2 | H | Filter/sort/fold over rows runs in `build()`; per-keystroke `setState` rebuilds the whole page (rule-1 violation). | `web_ledger_page.dart:357-364` |
| P3 | H | Donut `shouldRepaint` compares list **identity** (`old.slices != slices`); a fresh list each build → repaints every frame even with identical data. | `web_charts.dart:311` |
| P4 | H | Donut painter allocates `Paint()` per slice per frame and builds 2 `TextPainter`s every animation tick. | `web_charts.dart:266-304` |
| P5 | H | Page-level aggregation/sort in `build()` across bills, budget, history, dashboard (rule-1 violations) — needs presenter getters. | bills:65-77, budget:98-131, history:133-156, dashboard:607-771 |
| P6 | M | Single `ListenableBuilder` wraps each whole page → every notify rebuilds all cards + replays chart animations. | all pages |
| P7 | M | `IntrinsicHeight` around two-column card rows forces a speculative double layout pass each frame. | bills:110, history:239, dashboard:870 |
| P8 | M | No `RepaintBoundary` around animating charts; ticks can dirty the surrounding card layer. | `web_charts.dart` |
| P9 | M | O(rows×accounts) name/category lookups per build via `.where().firstOrNull` scans. | web_ledger:138-200, bills:599 |
| P10 | L | `DateFormat` allocated per build / per row instead of `static final`. | web_ledger, history |

### UX (desktop web)

| ID | Sev | Finding | File |
|----|-----|---------|------|
| U1 | H | One-click, irreversible **mark-paid** debits a silently-chosen account — no confirm, no undo, no success toast. | `web_bills_page.dart:558-610` |
| U2 | H | Destructive **bulk/single delete** in the ledger has no confirmation or undo. | `web_ledger_page.dart:275-286` |
| U3 | H | Charts have all interactivity **disabled** (`LineTouchData.enabled:false`, `BarTouchData.enabled:false`, donut not hit-testable) — desktop users expect hover tooltips. | `web_charts.dart:450,558` |
| U4 | M | Invisible delete button (`AnimatedOpacity(opacity:0)`) is still hit-testable → accidental deletes. | `web_ledger_page.dart:1940` |
| U5 | M | No Esc-to-cancel in inline editing; blur always commits. No search debounce. | `web_ledger_page.dart` |
| U6 | M | No Enter-to-submit on dialogs (account form, add bill); desktop users must mouse to the button. | account form, bills |
| U7 | M | Misleading empty state when filters/search yield zero matches ("add one below"); no error states anywhere. | ledger, all pages |
| U8 | M | Horizontal ledger scroll has no visible `Scrollbar`. | `web_ledger_page.dart:454` |
| U9 | L | Segmented/row controls use bare `GestureDetector` — no hover cursor/ripple. Receivables show a dead interactive checkbox. | ledger, bills |
| U10 | L | No reduced-motion honoring on progress bar + fl_chart animations. | charts, progress |

### Theme / Color (the "colors are bad" complaint)

| ID | Sev | Finding | File |
|----|-----|---------|------|
| T1 | H | Category palette (`kExpensePalette`/`kIncomePalette`) is **dark-mode-only** pastels (luminance ≈0.7–0.9), used for donut slices + goal bars → near-invisible on light-mode white cards. The >0.65-luminance fallback substitutes *another* light entry, compounding it. | `category_colors.dart`, dashboard, budget |
| T2 | M | `cs.onSurfaceVariant` (a text role) used as a **chart series fill** → weak contrast vs gridlines in light mode. | dashboard:334 |
| T3 | M | Swatch check-mark uses `cs.onPrimary` over an arbitrary user color → near-invisible on light swatches. | `web_account_form_dialog.dart:648` |
| T4 | M | Hardcoded `Colors.blue` swatch-parse fallback (rule-7 violation). | `web_account_form_dialog.dart:579` |
| T5 | L | Hardcoded `Colors.black` donut-popover shadow; reads too heavy in light mode. | `web_ledger_page.dart:934` |
| T6 | L | Hover tint `onSurface @ 0.03` is below perceptual threshold in dark mode. | `web_ledger_page.dart:1809` |
| T7 | L | Painter text styles hardcode size/weight instead of deriving from `textTheme` (won't honor text scaling). | `web_charts.dart:280-300` |

### Design-system gaps

| ID | Finding |
|----|---------|
| D1 | `_categoryLabel`/`_typeLabel` switch triplicated → `extension AccountCategoryLabel`. |
| D2 | Hex-parse triplicated with three different fallbacks → one `parseHexColor()` util. |
| D3 | Empty-state anatomy duplicated → `WebEmptyState` widget. |
| D4 | Dialog chrome (header/dividers/footer) hand-rolled per modal → `WebDialogScaffold`. |
| D5 | `main_web_preview.dart` is a throwaway harness that **writes to real persisted storage** and contains real-looking personal balances — must NOT be committed. |

---

## Plan — grouped commits

**G1 — Security hardening.** Release `debugPrint` no-op in `main_web.dart`
(`if (kReleaseMode) debugPrint = (_, {wrapWidth}) {};`); throw (not `assert`) on
missing required env in `auth_service`; client-ships header comment in `.env`
loader; CSP + `X-Frame-Options`/`Referrer-Policy` documented in `web/index.html`
(via meta where Flutter-safe, otherwise a hosting-headers comment block); fix
`web/manifest.json` placeholder hex/description; doc RLS expectation (S2) and
sign-out flush caveat (S7) in the spec. *(S1/S2/S5 are verify+document; S4/S6 are code.)*

**G2 — Correctness.** C1 (parentAccountId/category orphan), C5 (icon preserve),
C2 (outstanding tile → `totalUnpaidObligations`), C6 (numeric validators), C7
(save-failure catch+toast), C10 (custodian dropdown guard), C11 (mounted guard),
C12 (dead clause), C9 (`firstOrNull` guards). Ledger C3/C4/C8 move with G4/G5
since they share the row-rewrite.

**G3 — Light-mode color system.** Make `category_colors.dart` brightness-aware:
`resolveSliceColor(hex, index, {required Brightness brightness})` darkens
palette/parsed colors via HSL when `brightness == light`; add a
`Theme.of(context).brightness`-aware call site update across dashboard/budget.
T2 (chart series token), T3/T4 (swatch contrast + fallback), T5/T6 (shadow/hover
tints), T7 (painter text from `textTheme`).

**G4 — Performance.** Presenter: revision-counter memoization of
`ledgerSpreadsheetRows` + `_accountBalanceByTxnId` (invalidate on mutation);
new getters to lift `build()` math out of bills/budget/history/dashboard;
id→name/category `Map`s. Charts: `listEquals` `shouldRepaint`, hoist `Paint` +
cache `TextPainter`, `RepaintBoundary` wrappers, `DateFormat` statics. View:
search debounce; key inline cells on `t.id` only with `didUpdateWidget` sync
(C3); drop `IntrinsicHeight` (P7).

**G5 — UX polish.** Confirm dialogs for mark-paid (U1, showing amount+account)
and ledger delete (U2, bulk + single); `IgnorePointer` on the invisible delete
button (U4); Esc-to-cancel inline edit (U5); horizontal `Scrollbar` (U8);
hover-cursor on segmented controls (U9); enable themed chart hover tooltips (U3);
reduced-motion guard (U10); enter-to-submit on dialogs (U6); filtered-empty +
error states (U7). Ledger: presenter `deleteTransactions(Set)` (C8) and
`updateTransactionFields(id, …)` patch API (C4).

**G6 — Design-system.** `WebEmptyState`, `parseHexColor()` util,
`AccountCategoryLabel` extension, `WebDialogScaffold`; rewire pages to them.

**Excluded from commits:** `main_web_preview.dart` stays untracked (D5).

## Verification
- `dart format` on every changed file (repo rule).
- `flutter analyze` clean on changed files.
- Manual: toggle light/dark on each page; resize 840→1600 px.
