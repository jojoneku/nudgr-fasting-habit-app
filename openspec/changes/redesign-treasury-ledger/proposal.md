## Why

The Ledger is the second Treasury tab in the Nudgr redesign and the screen users touch most after the
Dashboard. An earlier increment already brought the transaction rows close to the reference
(`Nutrition Focus Treasury.dc.html`) with a name-based category-icon **heuristic**. This change
completes the Ledger reskin to the reference as a **superset** — adopting the reference's visual
language for the whole screen while keeping every existing capability (chat/AI logging, the unified
Filter & sort sheet, sort, month grid, day filter, transfers, reimbursables, swipe-delete + undo,
daily-net badge). It also promotes category iconography from an inferred glyph to a **user-settable**
choice, since the reference treats the icon as a category's identity.

## What Changes

- **Header layout (reference).** A `Ledger` title on its own row; below it a single controls row with
  the **Filter & sort** pill (left) and the **month/year** pill (right) in line. The standalone
  centered month row is removed; the day filter stays inside the Filter & sort sheet.
- **Segmented IN / OUT / NET strip.** Replace the three separate summary chips with one card split
  into three equal columns (green IN, red OUT, blue NET; NET turns red when the month is in deficit),
  values in JetBrains Mono. Fed by the existing presenter getters.
- **"No background" transaction rows.** Drop the per-row card fill; rows sit directly on the screen
  background. The category identity is carried by the **color-tinted category icon**; the subtitle is
  the **account name only** (falls back to the category when a txn has no account). Amounts stay
  semantic — expense red, income green, transfer neutral grey.
- **User-settable category icons, with a name-monogram fallback.** Add a catalog picker
  (`utils/category_icon_catalog.dart`) to the Manage Categories sheet; the choice persists in the
  existing `FinanceCategory.icon` field. The badge resolves as: chosen catalog icon → keyword-heuristic
  glyph → **name monogram** (initials in the category color) → per-type generic icon. The monogram
  step keeps categories the heuristic can't match (e.g. "Allowance") visually distinct instead of all
  collapsing to a generic receipt. Legacy categories need **no data migration**.
- **Taller chat input.** Keep chat logging; restyle the input pill and send button taller per the
  reference. Voice/TTS is deferred.

Non-breaking. No presenter/model/storage/navigation change; `FinanceCategory.icon` already persists,
so the picker needs no migration.

## Non-goals

- **No presenter/business-logic change.** `LedgerPresenter` keeps its public API; this is view/util
  only. Parsing, chat/AI logging, grouping, filtering, and persistence are untouched.
- **No text-to-speech / voice input.** The reference's blue mic is deferred; the current send-arrow
  affordance stays.
- **No data migration.** The picker writes the already-persisted `FinanceCategory.icon`; legacy values
  route through the name heuristic.
- **No new dependencies.** Material icons only (no Phosphor).
- **No changes to the web Treasury ledger table or other tabs** (Dashboard, Bills, Budget, History).

## Capabilities

### New Capabilities
- `treasury-ledger`: The Treasury Ledger tab — reference header (title + in-line Filter&sort/month
  pills), a segmented IN/OUT/NET strip, "no background" transaction rows whose identity is a
  color-tinted, **user-chosen** category icon (with a name-heuristic fallback and the reserved
  transfer glyph) over an account-only subtitle and a semantically-colored amount, plus a taller chat
  input — all theme-aware, preserving the row's edit/delete/undo and every existing Ledger feature.

### Modified Capabilities
<!-- None at the spec level beyond the treasury-ledger capability this change owns. openspec/specs/
     contains only `hub`; no other capability's requirements change. -->

## Impact

- **New:** `lib/utils/category_icon_catalog.dart` (`kCategoryIconCatalog`, grouped picker list,
  `resolveCategoryIcon`) — reusable by budget/dashboard tabs later.
- **Modified:**
  - `lib/views/treasury/ledger/ledger_view.dart` — header title row, in-line controls row
    (Filter&sort + month pill), segmented IN/OUT/NET strip, no-bg rows, taller chat input.
  - `lib/views/treasury/ledger/transaction_list_tile.dart` — stored-icon rendering, account-only
    subtitle, reference sizes, semantic amount colors (transfer → neutral grey).
  - `lib/views/treasury/ledger/manage_categories_sheet.dart` — category icon picker + live preview.
- **Reuses (unchanged):** `LedgerPresenter`, `category_icon.dart` (now the heuristic fallback),
  `AppIconBadge`/`AppListTile`/`AppNumberDisplay`, `finance_format.dart`, theme tokens.
- **Deps:** none new. **Risk:** low — view/util only, no presenter/model/storage change; legacy
  categories keep a sensible glyph via the heuristic fallback, so no row renders worse than before.
