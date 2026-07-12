## 1. Ring painter — opt-in full circle

- [x] 1.1 Add a `gapFraction` param to `PartialRingPainter` (default = current `0.2`) and thread it through `AppRingProgress`; full circle = `0`.
- [x] 1.2 Verify `timer_tab` and `activity_screen` (which reuse the painter) are visually unchanged (default gap preserved).

## 2. Three-ring hero

- [x] 2.1 Create `lib/views/widgets/hub/hub_rings_hero.dart` composing three `AppRingProgress` (full circle) — Fast / Food / Move — with center value + label and caption below.
- [x] 2.2 Wire data: Fast (fasting countdown + progress), Food (kcal vs goal), Move (steps vs goal) from Fasting/Nutrition/Activity presenters; all nullable-safe.
- [x] 2.3 Implement idle state (value 0 + glyph center + plain caption) and Food over-goal state (danger color, full, "+N OVER").
- [x] 2.4 Domain colors via `context.appColors.fast/food/move` + `fastTrack/foodTrack/moveTrack`; danger via `colorScheme.error`.

## 3. Header + coaching line

- [x] 3.1 Add a streak pill (flame + count) to the header using `NutritionPresenter.logStreak`.
- [x] 3.2 Add an AI coaching line: new async `hubNudge`/`refreshHubNudge()` on `AiCoachPresenter` (off-build generation from a compact state summary), a neutral fallback string, and mood tint (neutral/urgent/positive) from state. Hub shows cached/fallback immediately, updates on completion.

## 4. Rich Finance card

- [x] 4.1 Use the existing `forecastedNetBalance` getter for the hero (no new getter); net-worth variant at month-end.
- [x] 4.2 Rework Finance card: hero (forecasted ending balance / month-end net-worth), in/out cashflow bars, savings-rate chip, upcoming-bill countdown list; keep monthly summary + embedded quick-log reachable.

## 5. Preserve + pair cards

- [x] 5.1 Pair Weight + Body into a compact 2-up row.
- [x] 5.2 Surface the Stats/Character card (remove `SizedBox.shrink()`, add to base order, de-prioritised); keep Activity (distance) + Nutrition macro cards (design Open Q4).

## 6. Compose the Hub

- [x] 6.1 In `hub_screen.dart`, add the hero + coaching line as leading slivers above the `SliverReorderableList`; keep the pinned app bar and docked quick-log bar.
- [x] 6.2 Confirm drag-to-reorder still works with the fixed leading content and that card ordering persists.
- [x] 6.3 Ensure the docked quick-log bar stays pinned to the bottom (keep it as `bottomNavigationBar`, not inside the scroll).

## 7. Adaptive hero + macro-split ring

- [x] 7.1 Build a macro-split ring (segmented donut: 3 proportional P/C/F arcs summing to full, macro colors) — separate painter or a `segments` mode on the ring widget.
- [x] 7.2 Add hero-slot configuration (persisted via SettingsPresenter) resolved by a pure helper/presenter; default Fast/Food/Move.
- [x] 7.3 Auto-default slot 1 to the macro-split ring when the user doesn't fast (no fasting goal / no fast ever started); add a settings override.

## 8. Hub micro-actions

- [x] 8.1 Quests: inline "Mark done" on the surfaced quest → `QuestPresenter.completeQuest`; card updates in place.
- [x] 8.2 Weight: tap tile → inline single-value quick-entry (local widget state) with **Save + Cancel** → existing weight save; tile updates. Body: tap tile → **open the full multi-field body-measurement entry** (not inline), since body has more than one measurement.
- [x] 8.3 Finance: "Pay" on an upcoming bill → confirm sheet (`AppBottomSheet`) with amount + a source-account selector reusing the existing `DropdownButtonFormField` account picker (`initialValue`, preselected to `bill.accountId`) → `BillsReceivablesPresenter.markBillPaid(id, paidAmount:, accountId:)` (the real method; spec's `payBill` does not exist); never commit without confirm. No native/HTML picker.
- [x] 8.4 Keep one primary micro-action per card (no button farms); verify immediate state refresh.

## 9. Verification

- [x] 9.1 `dart format` + `flutter analyze` clean (0 new warnings).
- [x] 9.2 Full `flutter test` green (763 passed); added ring-state/hero-slot/coach-mood unit tests + hub degradation, mark-done, inline-weight-save, pay-confirm-gating, and macro-ring/no-fasting-default tests.
- [x] 9.3 Scoped harness (`lib/main_hub_preview.dart`, "Hub Preview" launch config) compiles & runs the real ring widgets with no console/build errors across active/idle/over-goal/no-fasting states. Dark + light rendering verified via automated both-themes render tests (`hub_theme_test.dart`) — no overflow/exceptions. NOTE: a still screenshot couldn't be captured (Flutter-web continuous render loop vs. the screenshot tool); the both-themes tests are the substitute proof.
- [x] 9.4 All `specs/hub/spec.md` scenarios confirmed: three-ring hero (active/idle/over), header+streak, non-blocking coaching line + fallback, rich Finance card, Weight+Body 2-up, reorder retained + hero pinned, preserved Activity/macros/Stats reachable, graceful degradation, configurable hero + macro-split + non-faster default + manual override, pinned quick-log, and micro-actions (mark-done, inline weight, body full entry, pay-with-confirm + selectable account + no silent mutation).
