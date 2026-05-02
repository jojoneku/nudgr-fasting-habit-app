# Plan 017a — Hub Dashboard & Navigation

> Depends on **017** (tokens + theme) and **017W** (widget library) being merged.

## Goal

Replace the "module launcher grid" with a true **dashboard**: a single vertical scroll of module cards that show live snapshots and one-tap quick actions. Cards with active state (currently fasting, overdue quest, bill due today) hoist to the top. The hub stops being a directory and starts being the place where you actually do things.

---

## UX Direction

### Page Chrome
- `AppPageScaffold.large(title: 'Today')` — collapsing large title (HIG canonical for top-level destinations)
- Subtitle slot: today's date in low-emphasis (e.g. *"Sunday, May 2"*)
- Pull-to-refresh: `onRefresh` re-pulls every module's hub summary
- Body is a `CustomScrollView` with `SliverList` of cards (since `.large` requires slivers)

### Layout: single vertical scroll, priority-ordered

The hub renders **one card per module**, in this order:

1. **Active cards first** — anything currently happening, ordered by how time-urgent they are:
   1. Fasting (if currently in a fast)
   2. Quests (if any are overdue or due today)
   3. Treasury (if any bill is due in the next 24h)
2. **Standard cards** — fixed default order:
   1. Nutrition (always relevant — daily kcal target)
   2. Activity (always relevant — daily steps)
   3. Treasury (if not already hoisted)
   4. Quests (if not already hoisted)
   5. Fasting (if not already hoisted — shows "ready to start" state)
   6. Stats (least time-sensitive — just progress)

If nothing is active, the list is just the standard order. No grid, no special hero treatment — the priority order itself is what gives active cards prominence.

### Card states: every card has two visual modes

| State | When | Look |
|---|---|---|
| **Active** | Module is currently in progress (fasting / due quest / bill imminent) | Taller card, richer snapshot (ring/progress visible), primary-color accent on the leading icon, prominent quick action |
| **Idle** | Module is in its default state | Standard card, compact snapshot (just text values), neutral leading icon, secondary quick action or no action |

Each `*HubCard` widget decides its own state from its presenter's `hubSummary`. The hub doesn't know.

### Card anatomy (consistent across modules)

```
┌────────────────────────────────────────────┐
│ [icon]  Module name                  >    │   ← header row (leading badge, title, chevron — entire card tappable)
│                                             │
│   {snapshot — module-specific UI}          │   ← child slot (varies per module)
│                                             │
│ ─────────────────────────────────────────  │   ← divider (only if quick action present)
│   {quick action button or row}             │   ← footer slot (omitted on read-only cards)
└────────────────────────────────────────────┘
```

Built on `AppCard` (filled variant default — HIG): header / child / footer slots match `AppCard`'s API exactly.

Tap behavior:
- **Tapping the card surface (anywhere outside the quick action button)** → navigate to the full module page
- **Tapping the quick action button** → executes the action (does NOT navigate); button uses `stopPropagation` semantics

---

## Per-module card spec

| Card | Snapshot (idle) | Snapshot (active) | Quick action |
|---|---|---|---|
| `FastingHubCard` | "Ready to start" + last protocol used | `AppRingProgress` (compact 80px) + remaining time + phase label | **Idle:** "Start fast" → starts default protocol. **Active:** "End fast" → opens completion modal |
| `NutritionHubCard` | Today's kcal `1,840 / 2,200` + 3 macro mini-`AppLinearProgress` bars | Same as idle (always "active") | "Log meal" → opens `add_food_sheet` |
| `QuestsHubCard` | "All caught up" empty state | Next due quest title + due time + XP `AppBadge` | **Active:** "Mark complete" on next due. **Idle:** no quick action |
| `ActivityHubCard` | Today's steps + progress bar + active minutes | Same as idle | None (read-only — tap to open) |
| `TreasuryHubCard` | Today's spend in DM Mono + remaining budget pill | Adds "Bill due in Xh" warning row | "Log expense" → opens `add_transaction_sheet` |
| `StatsHubCard` | Rank pill + level + XP bar to next level | Same (always idle) | None (read-only) |

Each card lives in `lib/views/widgets/hub/{module}_hub_card.dart` — these are **feature compositions**, not system primitives, so they don't belong in `widgets/system/`.

---

## Architecture

### `HubPresenter` (new)
> Decides card ordering. Doesn't hold module data — each card subscribes to its own presenter.

```dart
class HubPresenter extends ChangeNotifier {
  HubPresenter({
    required FastingPresenter fasting,
    required QuestsPresenter quests,
    required TreasuryPresenter treasury,
    // ... etc
  });

  /// Ordered list of card types — recomputed when any source presenter notifies.
  List<HubCardType> get cardOrder;
}

enum HubCardType { fasting, nutrition, activity, treasury, quests, stats }
```

**Notes:**
- `HubPresenter` listens to each module presenter; on any notify, recomputes `cardOrder` based on each module's "active" predicate (e.g. `fasting.isFasting`, `quests.hasOverdue`, `treasury.hasBillDueWithin24h`).
- Active priority: fasting > quests > treasury. Within a tier, the most recently changed wins.
- View binds via `ListenableBuilder(listenable: hubPresenter, …)` and renders cards in that order.

### Per-module presenter additions
> Each module's presenter exposes a small "is this currently active?" getter. No new state, just a derivation of existing state.

| Presenter | New getter |
|---|---|
| `FastingPresenter` | `bool get isFastActive` (already exists or trivial) |
| `QuestsPresenter` | `bool get hasUrgentQuest` — at least one due-today or overdue |
| `TreasuryPresenter` | `bool get hasBillImminent` — bill within 24h |
| `NutritionPresenter` | (none — always idle-state) |
| `ActivityPresenter` | (none) |
| `StatsPresenter` | (none) |

These additions are tiny (1-3 lines each) and ship as part of 017a — module page plans don't need to be touched.

### Hub cards subscribe directly
Each `*HubCard` is wired to its own module's presenter via constructor injection. The card uses `ListenableBuilder` internally to update live (no manual refresh). Hub itself doesn't pipe data — it just decides order.

---

## Files Touched

| File | Action |
|---|---|
| `lib/views/tabs/hub_screen.dart` | Full rewrite — `AppPageScaffold.large` + `CustomScrollView` + sliver list of cards driven by `HubPresenter.cardOrder` |
| `lib/presenters/hub_presenter.dart` | **Create** — orchestrates card ordering |
| `lib/views/widgets/hub/fasting_hub_card.dart` | **Create** |
| `lib/views/widgets/hub/nutrition_hub_card.dart` | **Create** |
| `lib/views/widgets/hub/quests_hub_card.dart` | **Create** |
| `lib/views/widgets/hub/activity_hub_card.dart` | **Create** |
| `lib/views/widgets/hub/treasury_hub_card.dart` | **Create** |
| `lib/views/widgets/hub/stats_hub_card.dart` | **Create** |
| `lib/presenters/fasting_presenter.dart` | Add `isFastActive` getter (likely already exists; verify) |
| `lib/presenters/quests_presenter.dart` | Add `hasUrgentQuest` getter |
| `lib/presenters/treasury_presenter.dart` | Add `hasBillImminent` getter |
| `lib/views/fasting_app.dart` | Wire `HubPresenter` into the widget tree (constructor injection from existing presenters); update `NavigationBar` labels |
| `lib/views/widgets/module_card.dart` | **Delete** (replaced by per-module hub cards). Confirm no other view references it before removing. |
| `lib/views/home_screen.dart` | Audit any header chrome above the hub — should now be empty since `AppPageScaffold.large` owns the header |

---

## Navigation Bar (unchanged from prior 017a draft)

- Sentence-case labels: "Hub", "Stats", "Settings"
- Active indicator: theme-default M3 pill, no glow
- Icon set: Material Symbols Outlined (inactive), Filled (active)
- Touch target ≥ 44×44px

---

## Design-System Widgets Consumed

`AppPageScaffold.large` · `AppCard` (filled, with header/child/footer slots) · `AppIconBadge` · `AppNumberDisplay` · `AppLinearProgress` · `AppRingProgress` (compact size in fasting card) · `AppStatPill` · `AppBadge` · `AppPrimaryButton` (compact variant in quick actions) · `AppEmptyState` (within quests card when caught up) · `AppPressable` (built into `AppCard`)

---

## Acceptance Criteria

- [ ] Hub renders as a single vertical scroll, no grid
- [ ] `AppPageScaffold.large` title collapses smoothly on scroll
- [ ] Card order recomputes when any module presenter notifies (active state changes)
- [ ] Tapping a card surface navigates to the module page
- [ ] Tapping a card's quick action executes the action and does **not** navigate
- [ ] Active state visually distinct from idle on every card that has both states
- [ ] Pull-to-refresh works without jank
- [ ] All cards use `AppCard` (filled variant default — no border-glow, no hardcoded shadows)
- [ ] No all-caps text on hub or nav bar
- [ ] Touch targets ≥ 44×44px on every card surface and every quick action button
- [ ] Light + dark mode both render correctly
- [ ] `module_card.dart` deleted with no broken references

---

## Out of Scope

- Module page redesigns (covered by 017b–017g)
- Locked-module handling (no locking exists in this app)
- Hub-level customization (reorder cards manually, hide cards) — possible future plan
- Personalized greeting variations beyond date/time-based
- Widgets / quick actions beyond what's listed per card

---

## Risks & Open Decisions

| Risk / Decision | Note |
|---|---|
| Quest card "Mark complete" picks the wrong quest | Use the next due/overdue quest by `dueAt`. If multiple at the same time, alphabetical by name. Confirm with QuestsPresenter API. |
| Treasury "Log expense" sheet opens over the hub — but the user might expect to be on Treasury after | Stay on hub after sheet dismisses. Show `AppToast.success` on save. |
| Fasting card on idle: starts the *default* protocol. What if user wants to pick? | Long-press the quick action → `AppActionSheet` with protocol options. Tap = default. |
| Activity card has no quick action — does it look anemic? | Steps + active minutes + a small `AppLinearProgress` toward step goal is enough density. Tap-to-open the only interaction. |
| `HubPresenter` listens to 5+ presenters → potential rebuild storms | Coalesce in a microtask: only one `cardOrder` recompute per frame. Standard `ChangeNotifier` debounce pattern. |
| Cards wired to their own presenters may rebuild even when off-screen (sliver virtualization) | `ListenableBuilder` only rebuilds when its widget is in the tree, so off-screen sliver cards don't subscribe. Verify in QA. |

---

*Plan 017a — dashboard hub. Ships after 017 + 017W. Module pages (017b–g) are independent — hub cards display data even if the module pages still have their old layouts.*
