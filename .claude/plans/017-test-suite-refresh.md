# Plan 017 — Test Suite Refresh (post-UI-overhaul)

## Goal
Bring the test suite back to green after the 017 design-system overhaul. The UI was rewritten across hub, timer, stats, nutrition, quests, activity, treasury, auth, and settings — but most widget tests still assert the **old copy and structure** (uppercase "START FAST", "Today's Steps", lock icons on locked module cards, etc.).

This is **not** a feature plan — there is no new RPG behavior. The job is to update finders/expectations so they match the new design tokens, copy, and presenter wiring, and to keep coverage at the same layer it was before.

## Current Status (as of 2026-05-03)
- **Total:** 273 passing, 10 failing
- **Already updated** by the in-progress working copy:
  - `test/mocks.dart` — adds `HubPresenter`, `SettingsPresenter`; switches presenter mocks to `@GenerateNiceMocks` (matches the new presenter API surface and removes "missing stub" friction).
  - `test/mocks.mocks.dart` — regenerated.
  - `test/views/hub_screen_test.dart` — rewired for new `HubScreen(hubPresenter:, settingsPresenter:, …)` signature; lock icons replaced with `SizedBox.shrink`; new "Start fast" / "End fast" copy.
- **Still stale (failing):**
  - `test/views/timer_tab_test.dart` — 7 failures
  - `test/views/activity_screen_test.dart` — 3 failures

## Affected Files
| File | Action | Why |
|---|---|---|
| `test/mocks.dart` | Already modified — **commit as-is** | Adds `HubPresenter`/`SettingsPresenter` mocks; switches to NiceMocks |
| `test/mocks.mocks.dart` | Already regenerated — **commit as-is** | Generated output |
| `test/views/hub_screen_test.dart` | Already modified — **review then commit** | Rewired to new constructor + copy |
| `test/views/timer_tab_test.dart` | **Update** | Stale copy/structure assertions |
| `test/views/activity_screen_test.dart` | **Update** | Stale copy/structure assertions |
| `test/test_helpers.dart` *(new, optional)* | **Create** | Shared `_wrap` + viewport helper (see Risks) |
| `lib/` | **No change** | UI is the source of truth; tests follow |

## Failure Inventory

### `test/views/timer_tab_test.dart` (7 failures)
The 017b redesign changed the timer tab's copy and layout. Expectations to update:

| Old assertion (stale) | New reality (`lib/views/tabs/timer_tab.dart`) |
|---|---|
| `find.text('START FAST')` | `'Start fast'` (sentence case) — line 102 |
| `find.text('END FAST')` | `'End fast'` — line 101 |
| `find.text('Ready?')` | `'Ready to start'` — line 86 |
| `find.text('Fasting Time')` | Replaced by `_statusLabel` derived from `FastingPhase` |
| Default `'16:00:00'` display | Still shown but inside `AppNumberDisplay` — assert via the widget, not raw text |
| Protocol selector cards finder | Replaced by `ProtocolCard` component grid; assert by widget type |
| `tap(find.text('START FAST'))` flows | Update target text + use `tester.ensureVisible` if needed |

### `test/views/activity_screen_test.dart` (3 failures)
The 017f redesign restructured the activity screen.

| Old assertion (stale) | New reality (`lib/views/activity/activity_screen.dart`) |
|---|---|
| `find.text("Today's Steps")` | Step count shown via `AppNumberDisplay` inside `AppRingProgress`; no literal "Today's Steps" label |
| `find.text('Daily Goals')` | `'Daily goals'` (sentence case) — line 869 |
| Manual entry sheet — "Enter manually" trigger | Trigger label/icon may have moved into a menu — locate by the sheet's content (`'Steps taken today'` field at line 1035) instead of the trigger text |
| Trophy icon when goal met | Now `'Daily goal crushed!'` copy (line 217) plus a `Goal met` chip (line 425); assert on those instead of an icon-only finder |
| `tap(find.byIcon(Icons.tune))` for goal sheet | Goal sheet is still reachable; verify the new entry-point widget — likely an `IconButton` with a different icon or a menu item |

### Render overflows (warnings, not failures)
Several tests log `RenderFlex overflowed by 16 pixels` from `lib/views/widgets/system/foundation/app_card.dart:58`. Default `flutter_test` viewport is 800×600; the new hub cards are designed for taller phones. These don't fail tests today but produce noise. **Out of scope for fixing now**, but covered by the optional `test_helpers.dart` (see Risks).

## Approach

### Strategy
1. **No new layer of testing.** Replace stale string finders with current copy. Replace structural finders that broke (e.g., lock icons) with finders that target what the new UI actually renders.
2. **Prefer semantic finders over text** where the new UI uses widgets like `AppNumberDisplay`, `AppRingProgress`, `ProtocolCard`. These are stable identifiers; copy will keep churning.
3. **Use the regenerated `MockHubPresenter` / `MockSettingsPresenter`** for any test that pumps a screen pulling from those presenters (currently only `hub_screen_test`).
4. **Don't expand coverage in this plan.** The 017 overhaul touched many screens (nutrition, quests, treasury, auth, settings) that have **no widget tests today** — adding tests for those is a separate plan.

### Implementation Order
1. [ ] **Sanity check** the already-modified files (`test/mocks*.dart`, `test/views/hub_screen_test.dart`) — run them in isolation, confirm green.
2. [ ] **Update `test/views/timer_tab_test.dart`** — fix the 7 failures using the mapping above. Group changes by `setUp`/`group`/`testWidgets` block; one test per fix.
3. [ ] **Update `test/views/activity_screen_test.dart`** — fix the 3 failures.
4. [ ] **Run full suite** — `flutter test` should be 283/283 green (273 prior + 10 fixed).
5. [ ] *(Optional)* Add `test/test_helpers.dart` with a `pumpAtPhoneSize(tester, child)` helper that sets `tester.binding.window.physicalSizeTestValue` to a typical phone (e.g., 390×844) — silences the overflow warnings without touching `lib/`.
6. [ ] Commit. Suggested message: `test(017): refresh widget tests for design-system overhaul`.

## Risks & Edge Cases
- **Risk: brittleness of text-based finders.** The 017 polish phase is over but copy may shift again. *Mitigation:* lean on widget-type finders (`find.byType(AppNumberDisplay)`) where possible; keep text finders only for user-facing labels we expect to be stable.
- **Risk: render overflows are real bugs hidden by the test viewport.** The `app_card.dart:58` overflow at 132×92 px size suggests cards squeeze poorly on small widths. *Mitigation:* not fixing here — but flag in the commit message and consider a follow-up if it reproduces on real devices (small phones, split-screen).
- **Risk: NiceMocks silently return defaults instead of throwing on missing stubs.** This makes tests less strict. *Mitigation:* keep specific `when(...).thenReturn(...)` for any value the test actually asserts on, so a real divergence still surfaces.
- **Edge case: `MockHubPresenter.cardOrder`** — the new test stubs it with `HubCardType.values.where((t) => t != HubCardType.stats)`. If `HubCardType` gains/loses values later, this will silently render fewer cards. *Mitigation:* leave as-is for now; revisit if hub coverage expands.

## Out of Scope
- Adding widget tests for screens that never had them (nutrition, quests, treasury, auth, settings, login).
- Fixing render overflows in `lib/`.
- Visual regression / golden-file testing for the new design system.
- Updating model/presenter/service tests — they all still pass.

## Acceptance Criteria
- [ ] `flutter test` returns 0 failures (283/283 green or higher).
- [ ] No regressions: every test that passed before still passes.
- [ ] No new tests added except the optional `test_helpers.dart`.
- [ ] No changes under `lib/`.
- [ ] Commit follows Conventional Commits: `test(017): …`.

---
*Present this plan for approval before writing any code.*
