# Plan 017e — Quests Module Redesign

> Depends on **017** (tokens + theme) and **017W** (widget library) being merged.

## Goal

Quests are the gamified to-do/routine system. Make them feel like a polished task app with a light RPG accent — XP rewards visible but not dominant. Use design-system primitives end to end.

---

## Files Touched

| File | Action |
|---|---|
| `lib/views/quests/quests_tab.dart` | List rewrite using `AppPageScaffold`, `AppSection`, `AppListTile` |
| `lib/views/quests/quest_detail_view.dart` | Detail layout — `AppCard` blocks for description, schedule, rewards |
| `lib/views/quests/routine_editor_view.dart` | Form using `AppTextField`, `AppSegmentedControl`, `AppPrimaryButton` |
| `lib/views/quests/add_quest_sheet.dart` | Wrap with `AppBottomSheet` |
| `lib/views/quests/widgets/*` | Migrate any custom widgets to compose system primitives |

---

## UX Direction

### Quest List
- `AppSection` headers: "Today", "Upcoming", "Completed"
- Each quest = `AppListTile`:
  - Leading: `AppCircularProgress` with centered category icon — shows stat / completion progress at a glance
  - Title: quest name
  - Subtitle: schedule (e.g. "Daily" / "Mon, Wed, Fri" / "Weekly")
  - Trailing: `AppBadge` showing XP reward (e.g. "+25 XP")
  - `onDelete` on the `AppListTile` → swipe-to-delete with red background (replaces ad-hoc `Dismissible`); confirmed via `AppConfirmDialog`
  - Tap → detail view; long-press → `AppActionSheet` with Edit / Duplicate / Archive / Delete (delete `isDestructive`)
- Completed quests: muted via `disabledColor`, checkmark in leading slot
- Empty state: `AppEmptyState` "No quests yet" + CTA "Create one"

### FAB
- M3 default "Add quest" → `add_quest_sheet`

### Quest Detail
- Top `AppCard`: title, description, category icon
- Middle `AppCard`: schedule details — recurrence, next due, reminder time
- Bottom `AppCard`: rewards — XP, attribute boost (if any), streak contribution
- Action row at the bottom: `AppPrimaryButton` "Mark complete" + `AppSecondaryButton` "Edit"

### Routine Editor
- Single scrollable form
- Sections (`AppSection`): Basics, Schedule, Rewards
- Schedule frequency uses `AppSegmentedControl` (Daily / Weekly / Custom)
- Day picker for weekly: row of `FilterChip`s themed via 017
- Save = `AppPrimaryButton`

### Completion Animation
- Subtle scale + fade on tile when checked off, ≤ `AppMotion.appear` (200ms)
- XP reward appears as a temporary `AppToast` ("+25 XP earned")
- **No** screen-takeover overlay for routine completion

---

## Design-System Widgets Consumed

`AppPageScaffold` · `AppSection` · `AppCard` · `AppListTile` (with `onDelete`) · `AppCircularProgress` · `AppBadge` · `AppIconBadge` · `AppEmptyState` · `AppBottomSheet` · `AppActionSheet` (long-press menus) · `AppTextField` · `AppSegmentedControl` · `AppPrimaryButton` · `AppSecondaryButton` · `AppConfirmDialog` · `AppToast`

---

## Acceptance Criteria

- [ ] Quests list uses `AppListTile` (no custom rows)
- [ ] All sheets via `AppBottomSheet`
- [ ] No all-caps headers ("DAILY QUESTS" → "Today")
- [ ] XP rewards use `AppBadge` with consistent styling
- [ ] Empty state present
- [ ] Both modes render correctly
- [ ] Completion animation ≤ 200ms

---

## Out of Scope

- Quest scheduling logic / recurrence math (presenter untouched)
- New quest types or reward formulas
