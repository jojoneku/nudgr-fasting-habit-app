# Ledger Redesign Spec

## Overview

Reskin the Treasury **Ledger** page (`lib/views/treasury/ledger/ledger_view.dart`)
to match the `docs/design-reference/` "Nudgr Focus" prototype — new fonts, new
tokens, taller list rows, category **icons** as the color-coded identity of each
row — **without removing any existing functionality**.

This is a **superset**, not a 1:1 port. Where the reference shows less than the
app does today (e.g. it has separate Category/Account pills and no chat bar), we
keep the richer app behaviour and only adopt the reference's *visual language*.
Where the reference shows something the app lacks (e.g. the segmented IN/OUT/NET
strip, per-row category glyphs), we adopt it.

Nothing in this spec changes the `LedgerPresenter` business logic, RPG/XP math,
persistence, or the finance data model beyond wiring the already-existing
`FinanceCategory.icon` field into the picker and the row.

## User Story

As a user, I want the Ledger to look like the polished Nudgr Focus design — with
a clean title/month header, a compact IN/OUT/NET strip, and transaction rows
identified by a colored category **icon** — so logging and scanning my money
feels as premium as the rest of The System, while I keep every capability I have
today (chat logging, full filters, sort, transfers, reimbursables, swipe-delete).

## Scope

### In scope (reskin + superset)
1. **Header row** — `Ledger` title (left) on its own line.
2. **Controls row** — `Filter & sort` pill (left) and month/year pill (right)
   **in line** on one row (per confirmed layout decision).
3. **IN / OUT / NET strip** — the reference's single segmented card.
4. **Transaction rows** — reference "no-background" line-item style (no per-row
   card fill), category **icon** badge tinted with the category color, account
   name as subtitle (category name is *dropped from the row text* — the icon +
   color now carries the category identity).
5. **Category icons are user-settable** in the existing Manage Categories sheet
   (extend the account-icon picker pattern to categories).
6. **Chat logging retained**, restyled taller per the reference input pill.
7. **New fonts & tokens** — Plus Jakarta Sans (UI) + JetBrains Mono (numbers),
   read via `Theme.of(context)` / `context.appColors` (already implemented in
   `app_colors.dart` / `app_text_styles.dart`; this spec just ensures the Ledger
   uses them consistently).

### Explicitly retained (superset — do NOT remove)
- Chat/AI logging drawer, quick replies, clarify flow, hard-error chip.
- The single **Filter & sort** sheet (multi-select categories + accounts, owed
  toggle, Newest/Oldest/Largest/Smallest sort, day filter via the spending
  calendar). We keep this instead of the reference's two separate Category /
  Account pills.
- Day grouping with the **daily-net badge**.
- Swipe-to-delete + Undo, long-press action sheet, edit sheet, transfer legs,
  reimbursable "owed to you" filter, month/year grid popover.
- Manage Categories / Add Transaction / open-form affordances.

### Non-goals (deferred)
- **Text-to-speech / voice input** (the reference's blue mic). Keep the current
  send-arrow affordance; do not add voice this pass.
- No changes to the web Treasury ledger table (`lib/views/web/...`).
- No changes to Dashboard, Bills, Budget, History pages.

## Confirmed Layout (top → bottom)

```
┌─────────────────────────────────────────┐
│  Ledger                                   │   ← title row (left, 23/800)
│                                           │
│  [⚙ Filter & sort]        [ June 2026 ▾ ] │   ← controls row (in line)
│                                           │
│  ┌──────────┬──────────┬──────────┐       │   ← IN/OUT/NET strip (1 card)
│  │   IN     │   OUT    │   NET    │       │
│  │ ₱68,000  │ ₱41,305  │ +₱26,695 │       │
│  └──────────┴──────────┴──────────┘       │
│                                           │
│  Today                          +₱4,715   │   ← day header + daily-net badge
│   🍴  Jollibee lunch                −₱285 │   ← no-bg row, icon = category
│       GCash                               │      (subtitle = account only)
│   ⇄   To Maribank savings         ₱5,000  │
│                                           │
│  Yesterday                     −₱?,???     │
│   💼  Salary                    +₱34,000  │
│   🚗  Grab to office               −₱180  │
│   🛍  Groceries · SM              −₱2,340  │
├───────────────────────────────────────────┤
│  🏷  ✎   [ ✨ Log a transaction…    ] ( ↑ )│   ← chat input (taller)
└───────────────────────────────────────────┘
```

## Component Specs

All hex values below are the **canonical dark-mode** tokens from
`docs/design-reference/Nudgr Design Tokens.dc.html`. In code, **do not hardcode
these** — resolve them from `Theme.of(context).colorScheme.*` /
`context.appColors.*` so light mode works (CLAUDE.md rule #7). The hex is the
spec's source of truth for *which* token to pick.

| Reference hex (dark) | Token / Flutter source |
|---|---|
| `#131315` screen bg | `theme.scaffoldBackgroundColor` |
| `#1C1C20` card/pill bg | `cs.surfaceContainerHigh` (pills) / `cs.surfaceContainerLow` |
| `#2A2A2E` border | `cs.outlineVariant` |
| `#F7F7F8` text-primary | `cs.onSurface` |
| `#9A9FA8` text-tertiary | `context.appColors.textTertiary` |
| `#83878F` text-muted | `context.appColors.textMuted` / `cs.onSurfaceVariant` |
| `#2E90FA` fast·blue | `context.appColors.fast` / `cs.primary` |
| `#46BD6B` move·green | `context.appColors.move` / `cs.tertiary` |
| `#F6685E` danger·red | `context.appColors.danger` / `cs.error` |

### 1. Header title row
- Container padding: `13, 20, 0` (L/T maps to `EdgeInsets.fromLTRB(20,13,20,0)`).
- `Ledger`: `fontSize 23`, `FontWeight.w800`, `letterSpacing -0.02em ≈ -0.5`,
  color `onSurface`. Use `Theme.of(context).textTheme.headlineSmall`-derived
  style (Plus Jakarta Sans) rather than a raw `TextStyle`.
- Title sits alone on the row (no trailing content), left-aligned.

### 2. Controls row (Filter & sort + month/year, in line)
- One `Row`, `padding EdgeInsets.fromLTRB(16, 12, 16, 6)`,
  `mainAxisAlignment: spaceBetween`.
- **Left — Filter & sort pill:** reuse the existing `_FilterSortBar` button
  verbatim (funnel/tune icon + "Filter & sort" label + active-count badge +
  quick-clear ✕ when filters active). Keep its active-state blue treatment. It
  opens the existing `_FilterSortSheet` (unchanged).
- **Right — month/year pill:** reuse the existing `_MonthSelectorRow` pill
  (calendar icon + `monthLabel` + caret-down) opening the anchored
  `_MonthPickerPopover` grid. Restyle to reference: `bg surfaceContainerHigh`,
  `border outlineVariant`, `radius 999`, `padding 6px 12px`, label `12px w700`,
  caret `10px` muted.
- The old standalone centered `_MonthSelectorRow` row is **removed**; the pill
  moves into this shared row. The quick-clear ✕ stays attached to the filter
  pill (left cluster) so the two pills don't collide.

### 3. IN / OUT / NET strip
Replaces the current 3 separate `_SummaryChip` boxes with one segmented card
(reference "IN/OUT/NET" strip).
- Card: `bg surfaceContainerHigh`, `border outlineVariant`, `radius 13`,
  `padding 10px 13px`, `margin 16px horizontal`, full width, `Row`.
- Three equal `Expanded` columns, each `center`-aligned:
  - Label: `9px`, `w700`, `textTertiary`, uppercase (`IN` / `OUT` / `NET`).
  - Value: `13px`, `w800`, **JetBrains Mono** (`AppTextStyles.mono`),
    `marginTop 2`.
    - IN → `move`/`cs.tertiary` (green), value = `filteredMonthInflow`.
    - OUT → `danger`/`cs.error` (red), value = `filteredMonthOutflow`.
    - NET → `fast`/`cs.primary` (blue), value = `filteredMonthNet`
      with `+`/`−` prefix; if negative, red (`cs.error`) instead of blue.
- Between columns: `1px` vertical divider (`outlineVariant`), full height.
- Values come from the **existing** presenter getters — no new API.

### 4. Transaction row (no-background line item)
Rewrite `TransactionListTile` presentation to the reference row; **keep all
existing behaviour** (tap → edit, long-press → action sheet, swipe → delete+undo,
semantics label).
- **No per-row card.** Drop the `AppCard(variant: filled)` wrapper in
  `_buildTxnTile`; rows render directly on the screen background, separated only
  by spacing (reference "no bg color on the cards"). Keep swipe/dismiss.
- Row: `Row`, `gap 13`, `padding EdgeInsets.symmetric(horizontal: 6, vertical: 11)`.
  Effective row height ≥ 44 (touch-target rule satisfied by vertical padding +
  icon).
- **Leading icon badge** (this is the category identity now):
  - `40×40`, `radius 12`, background = category color at **14% alpha**,
    glyph `18px` in the **full category color**.
  - Icon resolved from the **stored** `FinanceCategory.icon` (see §Category
    Icons). Transfers use `Icons.swap_horiz_rounded` in `cs.primary`.
- **Title** = `txn.description`: `14.5px`, `w600`, `onSurface`, 1 line ellipsis.
- **Subtitle** = **account name only** (`account?.name`): `11.5px`, `textMuted`,
  `marginTop 2`, 1 line ellipsis. **The category name is removed from the row**
  — the colored icon conveys it. (Keep the account color dot? No — reference
  shows plain account text; drop the dot for a cleaner row. Account color still
  lives on the icon-less contexts elsewhere.) If a txn has no account, show the
  category name as the subtitle fallback so the row is never blank.
- **Trailing amount**: `14.5px`, `w700`, **JetBrains Mono**. Sign + color
  (semantic — retain the app's current meaning, not the reference's neutral row):
  - Outflow → `−₱x`, color `danger`/`cs.error` (red).
  - Inflow → `+₱x`, color `move`/`cs.tertiary` (green).
  - Transfer → `₱x`, color `textMuted`/`cs.onSurfaceVariant` (neutral grey).
  - *(This keeps the at-a-glance red/green scan on every row; it deviates from
    the reference no-bg frame, which shows expenses in neutral text, by product
    decision.)*
- Semantics label unchanged: `"<description>, <amount>, <account>"`.

### 5. Day group header + daily-net badge
- Header label (`Today` / `Yesterday` / `EEEE, MMMM d`): `12px`, `w700`,
  `textTertiary`, `padding 13,20,4`. (Currently upper-cased via `AppSection`;
  switch to reference casing — Title case "Today", not "TODAY".)
- **Retain** the daily-net badge on the trailing side: `+/−₱x`, `11px`, `w600`,
  JetBrains Mono, green/red/neutral by sign. (Superset — reference's no-bg frame
  hides it, but we keep the capability.)
- Rows within a group are a plain `Column` with small (`4px`) gaps.

### 6. Chat input bar (retained, taller)
Keep `_LedgerChatInputBar` behaviour (categories button, form button, AI text
field, send). Reference-taller styling:
- Container `bg cs.surface`, `padding EdgeInsets.fromLTRB(12, 10, 12, safeBottom+10)`.
- Leading icon buttons (`label_outline` → categories, `edit_outlined` → form):
  keep, 44×44 tap targets.
- Input pill: **height 52** (up from 44), `radius 26`, `bg surfaceContainerHigh`,
  `border outlineVariant @50%`; leading `auto_awesome` sparkle `16px` in `fast`;
  hint text from existing `_hint()`.
- Send button: circular 48×48 (up from 44), `fast` when enabled, up-arrow glyph,
  spinner while busy. **No mic** (TTS deferred).
- All existing gating (`canSend` only today; form always available) unchanged.

## Category Icons (make icons settable per category)

`FinanceCategory` **already has** an `icon` field (`String`, MDI-ish name), but
today the ledger row *ignores it* and infers a glyph from the category **name**
(`lib/utils/category_icon.dart`). We wire the stored field through and add a
picker — mirroring the account-icon system shipped in
`lib/utils/account_badge.dart` (`kAccountIconCatalog` + picker grid).

### New: `lib/utils/category_icon_catalog.dart`
- `const Map<String, IconData> kCategoryIconCatalog` — a **fixed, const** set of
  pickable Material icons (MUST stay const so icon-font tree-shaking works, same
  constraint as the account catalog). Cover the finance domain: food, groceries,
  transport, shopping, health, home, bills/utilities, entertainment, travel,
  education, gifts, pets, salary, bonus, refund, invest, business, savings,
  transfer, plus a generic `tag`.
- `const List<CategoryIconGroup> kCategoryIconGroups` — grouped for the picker
  (Food & drink, Transport, Home & bills, Shopping, Life & health, Income, …).
- `IconData resolveCategoryIcon(String iconKey, String? name, CategoryType type)`:
  1. If `iconKey` is a key in `kCategoryIconCatalog` → that icon.
  2. Else fall back to the existing keyword heuristic `categoryIcon(name, type)`
     — so **legacy categories** (icon = `'tag'`, `'bank-transfer'`, or any
     non-catalog string) still render a sensible glyph with **no migration**.

### Manage Categories sheet (`manage_categories_sheet.dart`)
- Add an **icon picker** to the add/edit category flow, adjacent to the existing
  color picker. Reuse the account picker's grid interaction
  (`account_badge_widget.dart` picker) — a scrollable grid of catalog icons
  grouped by `kCategoryIconGroups`; selecting one stores its **key** in
  `category.icon`.
- New categories default `icon` to a catalog key (keep `'tag'` as the generic
  default; ensure `'tag'` exists in the catalog).
- Live preview: show the chosen icon in a `40×40` badge tinted with the chosen
  category color (same badge used in the row).

### Transaction row wiring
- `TransactionListTile._categoryIcon()` calls
  `resolveCategoryIcon(category.icon, category.name, category.type)` instead of
  `categoryIcon(category.name, ...)`.

### Data model
- **No `FinanceCategory` schema change** — `icon` already persists via
  `toJson`/`fromJson`. No storage migration required.

## Presenter API

**No changes.** The redesign consumes existing surface:
- `filteredMonthInflow` / `filteredMonthOutflow` / `filteredMonthNet` (strip)
- `groupedTransactions` / `sortedTransactions` / `sortField` (list)
- `selectedMonth` / `setMonth` / month grid (month pill)
- `activeFilterCount` / `isCustomSort` / `clearAllFilters` / filter sheet getters
- `categories` / `addCategory` / `updateCategory` (icon picker persists via the
  existing `updateCategory` → `saveFinanceCategories`)
- chat state machine (`chatState`, `sendChatInput`, `confirmResolved`, …)

## UI Requirements
- **Thumb zone:** the chat input + send (primary log action) stays pinned to the
  bottom of the screen (bottom ~15%). Month/filter pills are secondary and may
  sit up top.
- **States:** Loading (existing skeleton/spinner), Empty (`AppEmptyState` "No
  transactions this month"), Populated, chat Error chip.
- **Glanceability:** IN/OUT/NET readable in < 1s; each row's category
  identifiable by icon+color at a glance.
- **Micro-animations:** keep the 200ms `AnimatedSize` chat drawer; month popover
  and swipe-delete keep current timings (150–300ms). No new animation > 400ms.
- **Touch targets:** every interactive element ≥ 44×44 (rows, pills, buttons).
- **Theme-aware:** all colors via `Theme`/`context.appColors`; verify both dark
  (default) and light render correctly. No `AppColors.X` / `AppColorsLight.X`
  inside widgets.

## RPG Mechanics
Unchanged. XP for logging transactions is awarded by `LedgerPresenter`
(`+25` first-ever, `+10` first-of-day) exactly as today; this is a
presentation-only redesign.

## Storage
- No new `StorageService` keys.
- `FinanceCategory.icon` continues to persist within the existing
  `saveFinanceCategories` payload.

## Edge Cases
- **Legacy category with a non-catalog `icon`** (`'tag'`, `'bank-transfer'`,
  old free-text) → `resolveCategoryIcon` falls back to the name heuristic; row
  still shows a meaningful glyph. No migration, no crash.
- **Uncategorized transaction** (`category == null`) → generic `tag`/receipt
  glyph in `cs.primary`; subtitle falls back to account, then category label.
- **Transaction with no account** → subtitle shows the category name (never a
  blank subtitle).
- **Transfer legs** → `swap_horiz` glyph, `cs.primary`, amount neutral/muted,
  "Transfer" as subtitle fallback; both legs still visible in All view.
- **Negative NET** → NET column turns red (`cs.error`) with `−` prefix instead
  of blue.
- **Amount sort active** → list is flat (no day groups); rows use the same no-bg
  style; the daily-net badge doesn't apply.
- **Viewing a past day** (chat gated to today) → input hint + gating unchanged.
- **Light mode** → icon-badge 14% tint and all text tokens must keep contrast
  (use light-variant tokens automatically via Theme).
- **Very long description / account name** → single-line ellipsis, amount never
  truncated (fixed trailing).

## Files Touched
| File | Change |
|---|---|
| `lib/views/treasury/ledger/ledger_view.dart` | Header title row; merge month pill + filter pill into one controls row; segmented IN/OUT/NET strip; taller chat input; no-bg row wrapper; Title-case day headers |
| `lib/views/treasury/ledger/transaction_list_tile.dart` | No-bg row layout; account-only subtitle; reference type sizes/colors; stored-icon rendering |
| `lib/views/treasury/ledger/manage_categories_sheet.dart` | Add category **icon picker** + live badge preview |
| `lib/utils/category_icon_catalog.dart` | **New** — `kCategoryIconCatalog`, groups, `resolveCategoryIcon` (falls back to `category_icon.dart`) |
| `lib/utils/category_icon.dart` | Keep as the heuristic fallback (unchanged) |

## Acceptance Criteria
1. Ledger header: `Ledger` title left; Filter & sort pill + month/year pill share
   one row below it; IN/OUT/NET strip below that.
2. IN/OUT/NET strip shows correct live values with green/red/blue coloring and
   `+/−` on NET (red when negative), in JetBrains Mono.
3. Transaction rows have **no card background**, a color-tinted category **icon**
   badge, description title, **account-only** subtitle, and a mono amount colored
   semantically: expense red, income green, transfer neutral grey.
4. Category identity is conveyed by the icon+color; the category **name no longer
   appears** in the row (except as an account-less fallback).
5. Users can pick a category icon in Manage Categories; the choice persists and
   immediately reflects in the ledger row.
6. Legacy categories with no catalog icon still render a sensible glyph (no
   migration, no blank).
7. All retained features work: chat logging, Filter & sort sheet, sort options,
   month grid, day filter, swipe-delete+undo, transfers, reimbursable filter,
   daily-net badge.
8. No TTS/voice added.
9. Both dark and light themes render correctly; no hardcoded `AppColors.*` in
   widgets.
10. `flutter analyze` clean; existing ledger widget tests pass (update
    expectations where row text/structure changed).
