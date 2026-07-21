## Context

The Ledger tab (`ledger_view.dart` + `transaction_list_tile.dart`) is a mature, feature-rich screen:
month selector + calendar popover, date/category/account/owed filters, an income/expenses/net summary
card, a day-grouped transaction list with daily-net badges and swipe-to-delete + undo, and an AI chat
drawer + input bar. It already mirrors the Nudgr reference (Frame 2) structurally: each row is an
`AppIconBadge` (category-colored) + title + "category · account" subtitle (with an account color dot)
+ a signed, type-colored amount.

The single visual gap from the reference is iconography: non-transfer rows use one generic
`label_outline_rounded` glyph, whereas the reference shows category-specific glyphs (fork-knife, car,
briefcase, shopping-bag). Categories in this app do not persist a usable icon — users create
categories by name only — so the glyph must be inferred.

This change extends that increment into a full reference reskin (header, cash-flow strip, "no
background" rows, taller chat input) and promotes the icon from an inferred glyph to a user-chosen
one — the reference treats a category's icon+color as its identity, and the row now drops the category
name from its text and leans on the icon to carry it.

## Goals / Non-Goals

**Goals:**
- Bring the whole Ledger screen to the reference's visual language (header title + in-line
  Filter&sort/month pills, segmented IN/OUT/NET strip, no-bg rows, taller chat input).
- Let users choose a category's icon; keep a name-heuristic fallback so nothing regresses and no
  migration is needed.
- Keep the icon helpers pure and reusable for later tabs (budget/dashboard breakdowns).

**Non-Goals:**
- Any change to `LedgerPresenter`, parsing, grouping, filtering, chat, or persistence semantics.
- Text-to-speech / voice input (deferred).
- A data migration — `FinanceCategory.icon` already persists.
- Changes to the web Treasury ledger table or other tabs.

## Decisions

- **Persisted, user-chosen icon with a heuristic fallback.** `resolveCategoryIcon(iconKey, name, type)`
  returns the catalog icon for an explicit `FinanceCategory.icon` key, else falls back to the earlier
  `categoryIcon(name, type)` heuristic. Rationale: the reference makes the icon a category's identity
  (the row no longer prints the category name), so users must be able to set it — but the field already
  exists and legacy values (e.g. `'tag'`, `'bank-transfer'`) simply route through the heuristic, so
  there is **no migration**. This reverses the earlier increment's "no picker / no persisted glyph"
  non-goal by design. *Alternative:* keep inference-only — rejected because identity-by-icon needs a
  deterministic, user-controllable glyph.
- **`'tag'` is the "Auto" sentinel, deliberately NOT a catalog key**, so the historical default and any
  legacy free-text still render the name-derived glyph.
- **Name-monogram fallback (mirrors the account badge).** Because the row drops the category name,
  two categories the keyword heuristic can't match would otherwise both show the generic receipt/arrow
  and read identically. `resolveCategoryBadge` instead returns a name monogram (initials in the
  category color) for unmatched names — the same identity trick accounts already use — and only uses
  the per-type generic icon when the name has no usable letters. The shared `CategoryBadge` widget
  renders either an icon or the monogram so every surface stays consistent.
- **Const icon catalog.** `kCategoryIconCatalog` is a fixed `Map<String, IconData>` (no dynamic
  codepoints) so icon-font tree-shaking keeps working in release — the same constraint the account
  icon catalog follows.
- **Order heuristic keywords specific-before-general** (e.g. "grocer" before "food") so the closest
  match wins; the fallback guarantees every row gets a valid glyph.
- **Amounts stay semantic** (expense red, income green, transfer neutral grey) rather than the
  reference's neutral no-bg amount, so the red/green scan reads on every row (product decision).
- **View/util only.** All new state is derived from the unchanged presenter; the row keeps its
  edit/delete/undo and long-press actions. Transfers keep their explicit swap glyph at the call site.

## Risks / Trade-offs

- **[Category name dropped from the row]** → identity now rests on icon + color, so a category with a
  default/auto icon and a muted color could read ambiguously. Mitigated by the account subtitle, the
  settable icon, and the name-heuristic auto glyph; the category name is still visible in Manage
  Categories and the filter sheet.
- **[Wrong heuristic glyph for an oddly-named auto category]** → worst case is a fallback receipt/arrow
  icon — never worse than the earlier generic icon. Covered by the keyword-map unit test.
- **[Catalog must stay const]** → dynamic `IconData` would break icon-font tree-shaking in release;
  `kCategoryIconCatalog` is const and only grows by adding entries.

## Migration Plan

None — the picker writes the already-persisted `FinanceCategory.icon`; legacy/unset values route
through the name heuristic via `resolveCategoryIcon`. View/util only; rollback is reverting the three
touched view files + the new catalog util.

## Open Questions

- Later: reuse `resolveCategoryIcon` in the Budget "by category" rows and the dashboard category
  breakdown so iconography is consistent across Treasury (out of scope for this increment).
