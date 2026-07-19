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

## Goals / Non-Goals

**Goals:**
- Give transaction rows reference-style, category-specific icons.
- Keep the helper pure and reusable for later tabs (budget/dashboard breakdowns).

**Non-Goals:**
- Any change to `LedgerPresenter`, parsing, grouping, filtering, chat, or persistence.
- A category-icon picker or persisted glyph, and any data migration.
- Restructuring the filter row, chat drawer, calendar popover, or input bar.

## Decisions

- **Name-based keyword heuristic, not a persisted glyph.** `categoryIcon(name, type)` matches
  lowercased name substrings against an ordered keyword table and returns a Material icon, with a
  per-`CategoryType` fallback (income → down-arrow, expense → receipt, transfer → swap). Rationale:
  categories carry no reliable icon field and users never pick one, so the name is the only signal;
  inferring at render time needs no model/storage change or migration. *Alternatives:* (a) add an
  icon field + picker — rejected as scope creep and a data migration for a visual nicety; (b) keep the
  generic icon — rejected as the whole point of the increment.
- **Order keywords specific-before-general** (e.g. "grocer" before "food"; "salary" before generic
  income) so the closest match wins. Fallback guarantees every row gets a valid glyph.
- **Wire only at the badge glyph.** `TransactionListTile._categoryIcon()` calls the helper; the badge
  color, subtitle, amount, and all interactions are untouched — minimizing blast radius.
- **Transfers keep their explicit swap glyph** at the call site (before the heuristic), matching the
  reference and the reserved transfer category.

## Risks / Trade-offs

- **[Wrong glyph for an oddly-named category]** → The badge color and text still identify it; the
  worst case is a fallback receipt/arrow icon — never worse than today's generic icon. Covered by a
  unit test over the keyword map.
- **[Keyword table drift over time]** → It's a pure function with a unit test; extending it is a
  one-line addition. Kept in `utils/` so budget/dashboard can share it later.

## Migration Plan

None — render-time inference, no data or storage change. Ships on `feat/redesign-treasury`; rollback
is reverting the row's one-line glyph source.

## Open Questions

- Later: reuse `categoryIcon` in the Budget "by category" rows and the dashboard category breakdown so
  iconography is consistent across Treasury (out of scope for this increment).
