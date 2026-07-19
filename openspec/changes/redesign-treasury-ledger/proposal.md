## Why

The Ledger is the second Treasury tab in the Nudgr redesign and the screen users touch most after the
Dashboard. It is already well-architected and structurally close to the reference
(`Nutrition Focus Treasury.dc.html`, Frame 2) — colored icon badges, day-grouped entries, a
category·account subtitle, and a signed/colored amount. The one distinctive reference detail it
lacks is **category-specific glyphs** (fork-knife for food, car for transport, briefcase for salary):
today every non-transfer row shows the same generic `label_outline` icon, so the list reads flatter
and less scannable than the reference. This is a **restyle** — bring the transaction rows to the
reference's per-category iconography — not a rebuild of the ledger flow.

## What Changes

- **Add a name-based category-icon heuristic** (`utils/category_icon.dart`): map a category to a
  representative Material icon from its name (grocer→cart, food/dining→fork-knife, transport/grab→car,
  salary→briefcase, rent→home, bills/utilities→bolt, health→medical, …) with a per-`CategoryType`
  fallback. Pure and side-effect-free; categories in this app don't persist a usable glyph, so the
  name is the only available signal.
- **Use it in the transaction row** (`transaction_list_tile.dart`): the leading `AppIconBadge` now
  shows the inferred glyph instead of the generic label icon; transfers keep their swap glyph and the
  account/amount styling is unchanged.
- **Verify the rest of the Ledger already matches the reference** — day headers (Today/Yesterday),
  filter chips (Category/Account), summary card, and input bar — and align any token drift. No
  structural change to the filter row, chat drawer, calendar popover, or month selector.

Non-breaking. No presenter/model/storage/navigation change; the row keeps its edit/delete/undo,
long-press actions, and account-dot subtitle.

## Non-goals

- **No presenter/business-logic change.** `LedgerPresenter` keeps its public API; this is view/util
  only. Parsing, chat/AI logging, grouping, filtering, and persistence are untouched.
- **Not a filter/chat/input-bar rebuild.** Those already read theme tokens and match the reference's
  intent; only token drift (if any) is corrected.
- **No user-facing category-icon picker** and no data migration — the glyph is inferred at render
  time, nothing is persisted.
- **No new dependencies.** Material icons only (no Phosphor).

## Capabilities

### New Capabilities
- `treasury-ledger`: The Treasury Ledger tab's transaction row iconography — a category is rendered
  with a representative Material glyph inferred from its name (with a per-type fallback and the
  reserved transfer glyph), inside the existing colored badge, preserving the row's edit/delete/undo
  and account·amount styling; theme-aware (no hardcoded per-mode colors).

### Modified Capabilities
<!-- None. openspec/specs/ contains only `hub`; there is no existing `treasury`/`ledger` capability,
     and no other capability's spec-level requirements change. -->

## Impact

- **New:** `lib/utils/category_icon.dart` (pure `categoryIcon(name, type)` helper) — reusable by the
  budget/dashboard tabs in later increments.
- **Modified:** `lib/views/treasury/ledger/transaction_list_tile.dart` (leading glyph source).
- **Reuses (unchanged):** `LedgerPresenter`, `TransactionListTile`'s badge/subtitle/amount,
  `AppIconBadge`/`AppListTile`/`AppNumberDisplay`, `finance_format.dart`, theme tokens.
- **Deps:** none new. **Risk:** low — the heuristic falls back to the current generic icon behavior
  for unmatched names, so no row can render worse than today; verified with a unit test over the
  keyword map and a widget test on the row.
