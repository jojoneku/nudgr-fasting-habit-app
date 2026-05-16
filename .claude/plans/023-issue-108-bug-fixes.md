# Plan 023 — Issue #108 Bug Fixes & Follow-ups

Source: GitHub Issue #108 ("Bug 1.0.55"). This plan covers the items that need
investigation or larger changes. Quick wins were merged inline.

## Status

| # | Item | Status |
|---|------|--------|
| 1 | Snackbar lingering/queueing | ✅ Fixed (AppToast hides current; ledger uses AppToast) |
| 2 | "BUDGETED EXPENSES" all caps | ✅ Fixed → "Budgeted Expenses" |
| 3 | Bill delete not in dashboard liabilities | 🔍 Plan A below |
| 4 | Goals/savings inside Budget | 🔮 Plan B below |
| 5 | AI crash on "red rice" | ✅ Soft circuit breaker + defensive createChat (native crashes still uncatchable) |
| 6 | Smartsearch "model not found" 404 | 🔍 Plan D below |
| 7 | "Check latest" stuck on already-on-latest | 🔍 Plan E below |
| 8 | Faint divider above meal totals | ✅ Fixed (always render `_MealTotalRow`) |
| 9 | Edit-meal: only delete, can't add items | 🔮 Plan F below |
| 10 | Confirmation prompt skipped (sapin sapin repeat) | ✅ Auto-learn now requires lexical match; learn-key strips quantity tokens |
| 11 | Fuzzy search ("bearbrand"/"pansit") | ✅ Shipped in commit 6a59b4a (compound splits + Damerau–Levenshtein) |
| 12 | "could not identify the exercise" on food query | ✅ Fixed (word-boundary match) |
| 13 | Account snapshots show raw IDs | ✅ Fixed (lookup by name) |
| 14 | Pie chart: glow, single income color, overflow | ✅ Glow removed; Plan I for top-N + colors |

---

## Plan A — Bill delete → dashboard sync

### Hypothesis

`BillsReceivablesPresenter.deleteBill` already calls `_notifyDependents()`
which awaits `_dashboard.load()`. Storage round-trip should rehydrate the
dashboard's `_bills`, and `upcomingBills` filters by `_currentMonth`. So the
chain looks correct.

The user's wording ("list of liabilities in dashboard") may refer to the
`UpcomingBillsCard`, OR to `_LiabilitiesCard` (which lists *liability accounts*,
not bills — different concept).

### Investigation steps

1. Reproduce: create a bill, switch to dashboard, swap back to Bills, delete,
   swap to dashboard. Watch the "Upcoming Bills" card.
2. Add a `debugPrint` on `_notifyDependents` and on `dashPresenter.load()` to
   confirm the chain fires.
3. Check whether the dashboard tab's `_onTabChanged` reload also runs (race
   between two `load()` calls).

### Likely fix

If bug confirmed in `UpcomingBillsCard`:
- Have `TreasuryDashboardPresenter` listen to `BillsReceivablesPresenter`
  directly (mirror pattern used for `LedgerPresenter` via `_syncFromLedger`),
  so updates propagate without a storage round-trip.

If user meant `_LiabilitiesCard`:
- Cross-link bills ↔ liability accounts. Adding a bill against a liability
  account should adjust the account balance; deleting it reverses. This is
  a behavior change — confirm intent before implementing.

---

## Plan B — Goals & savings inside Budget

User feedback:
> "i think we can add goals and savings to budget as well. like i do budget
> to save every month."

### Approach

- New `BudgetItemKind { expense, savings, goal }` (or reuse `BudgetGroup`).
- Allow budget allocation against a `goalAccount` / `savingsAccount` instead
  of an expense `FinanceCategory`.
- "Spent" semantics for savings = amount transferred *into* the account this
  month (treat inflow to savings/goal as the "spend").
- Budget presenter: add `savingsAllocations` and `savingsContributedByGroup`.
- UI: extend the budget tabs/sections — keep existing expense layout, add a
  "Savings" section.

Open questions:
- Does the existing `goalAccounts`/`savingsAccounts` capture progress per
  month, or just running balance? May need a monthly snapshot.

---

## Plan C — AI crash on "red rice"

User report: app crashed when AI was active and they typed "red rice".

### Investigation

1. Check `AiCoachService.extractFoodItems` — timeout is 25s but does it handle
   model-not-loaded / OOM gracefully?
2. Inspect Plan 022 matcher for input that returns ambiguous results.
3. Reproduce on emulator with logcat to capture the actual stack trace.

Most likely candidates:
- Native crash from gemma/llama runtime when a long prompt + low-RAM device.
- Unhandled future in `_hybridResolveItem` when the embedder is mid-init.

### Mitigation

- Wrap `extractFoodItems` in `runZonedGuarded` and degrade to NLP fallback on
  any error, not just typed exceptions.
- Ensure smartsearch is `ready` before allowing AI extraction (Plan D).

---

## Plan D — Smartsearch 404 "model not found"

### Findings

- `EmbeddingService` defaults to `EmbeddingModel.embeddingGemma300M4bit`
  → URL: `https://huggingface.co/google/embeddinggemma-300m-4bit/resolve/main/model.tflite`
- AI Coach uses `litert-community/Qwen3-0.6B` (different repo, working).
- The `embeddinggemma-300m-4bit` repo is the suspect — likely no longer
  exists or the file path changed. HF gating ≠ 404 (gating returns 401/403).

### Done

- Surfaced the actual download error to the UI via `_bundleError` in the
  Settings smartsearch enable path (was previously silent).

### Open

- Verify on HF whether `google/embeddinggemma-300m-4bit` still hosts
  `model.tflite`. If gone, switch default to `embeddingGemma300M` (300 MB,
  canonical) or `gecko110M` (110 MB, English-only).
- Optional: try variants in order (4bit → 8bit → 300M) on 404, so the user
  isn't blocked by a single removed file.

---

## Plan E — "Check latest" always says already on latest

Update presenter compares the running version against GitHub releases.

### Investigation

- `update_presenter.dart` — read the version comparison logic. Probably
  string-compares vs. semver-compares; "1.0.55" vs "1.0.5" or pre-release
  suffixes ("1.0.55-beta") may sort wrong.
- Also check whether the GitHub API filters drafts/prereleases — maybe the
  "latest" endpoint returns nothing for a prerelease channel.

### Fix sketch

- Use `pub_semver` for comparison.
- Hit `/releases` (list) and pick the first non-draft, optionally including
  prereleases when the user has opted in.

---

## Plan F — Edit-meal: allow adding items

Currently the meal-edit flow exposes only delete-row. User wants "+ add item".

### Approach

- `_ChatMessageCard._editing` mode: render a trailing "+ Add" tile that
  pushes `_FoodEditField` for a new line.
- Reuse `_hybridResolveItem` to commit the new entry into the message and
  the day's nutrition log.
- Recompute totals in place; no storage round-trip until the user saves the
  edit.

---

## Plan G — Confirmation skipped on repeat AI suggestion

User: "i was not asked for confirmation about red rice when it gave me sapin
sapin again."

### Investigation

When the AI's pick has confidence < 0.6 we render alternative chips
(`hybrid.confidence < 0.6 && hybrid.alternatives.isNotEmpty`). The
"needsConfirmation" badge gates this. If the same wrong pick has happened
before (cached in personal dict), it's now ≥ 0.75 confidence and skips
confirmation.

### Fix sketch

- Track per-item *user corrections* in personal dict — if user previously
  swapped X→Y, never auto-pick X for the same input phrase again. Demote
  confidence to force the chip.
- Add a "negative learn" path on swap.

---

## Plan H — Fuzzy match for food/exercise search

User: "pansit doesn't match pancit"; "bearbrand" doesn't hit unless typed
with a space.

### Approach

- `FoodDbService.search` currently uses FTS5 prefix match.
- Add a Levenshtein/Damerau-Levenshtein second pass when FTS yields zero
  hits, capped at edit distance 2.
- Tokenize on word boundaries AND attempt collapsed/expanded variants
  ("bearbrand" ↔ "bear brand", "ice cream" ↔ "icecream").
- For the chat parser, this fixes "pansit"; for manual search, fixes the
  "could not match" empty state.

---

## Plan I — Pie chart top-N + color fix

### Top-N

- `categorySpendThisMonth` already trims to 10 + Other.
- Reduce dashboard preview to 5 (top-3 strict if very crowded), keep the
  "View All" CTA which already opens `FullCategoryBreakdownSheet`. Use 5 for
  preview to leave the legend readable.
- Move `View All` chevron into the card footer when overflow exists.

### Colors

User says "all income are just the same color." The expense pie only shows
expense categories, but the user may be referring to `kIncomePalette` used
elsewhere, or to categories with the legacy white default falling through to
`kExpensePalette[index % palette.length]`.

- Audit `resolveSliceColor`: use the *category type* (expense vs income) to
  pick the right palette on fallback, not the implicit "expense" assumption.
- Dedupe colors across slices: if two slices resolve to the same hex, the
  second pulls the next palette entry.
