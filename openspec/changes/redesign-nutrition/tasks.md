## 1. Presenter & util groundwork (land before UI)

- [x] 1.1 Add a read-only `NutritionPresenter` getter returning `chatMessages` ordered newest-first for the "Today's log" list (no meal-slot grouping). Day total reuses existing `todayCalories`. Unit-test ordering.
- [x] 1.2 Confirm hero getters exist (eaten `todayCalories`, `remainingCalories`, `calorieProgress`, `isOverGoal`, `todayProtein/Carbs/Fat` + `proteinProgress/carbsProgress/fatProgress`, `selectedDateCaloriesBurned`); add only if missing. All present — no new getters needed.
- [x] 1.3 Entry actions bind to existing message-keyed presenter methods (`removeChatMessage`, `markChatMessageDisliked`, `saveFoodTemplate`, `editAllChatFoodItems`). Added one additive presenter method `restoreChatMessage` for delete-undo (mirrors `removeChatMessage`), covered by 2 unit tests in `food_logging_pipeline_test.dart` (23/23 green). Did NOT regenerate `test/mocks.mocks.dart`.

## 2. Shared widget extraction (no visual change yet)

- [x] 2.1 Create `lib/views/nutrition/widgets/` and move the calorie/macro card, log rendering, and input bar out of `nutrition_screen.dart` into stub widgets with identical behavior; confirm `flutter analyze` clean and existing tests green. [analyze clean; on-device smoke pending]
- [x] 2.2 Reduce `nutrition_screen.dart` to a thin scaffold (header + date strip + body + pinned bar) delegating to the extracted widgets; no logic in `build()`. [analyze clean; on-device smoke pending]

## 3. EATEN TODAY hero (restyle of the stat card)

- [x] 3.1 Build `eaten_today_hero.dart` — gradient card: "EATEN TODAY" label, big eaten kcal, left-of-goal in the domain accent, calorie progress bar, P/C/F columns with mini-bars. Theme tokens only; Material icons.
- [x] 3.2 Wire over-goal state (danger color) and keep tap → existing breakdown sheet (which still shows Burned + per-macro detail). Verify under/over-goal and tap-through. [analyze clean; on-device visual smoke pending]

## 4. Today's log (flat list)

- [x] 4.1 Build `nutrition_log_list.dart` rendering the presenter's flat entry list (§1.1): "Today's log" label + day total kcal, then `_LogEntryCard`s newest-first — no meal-slot section headers. [analyze clean; on-device smoke pending]
- [x] 4.2 `_LogEntryCard`: name, sub-line (amount/grams · time), source badge (Cloud/Local/Library), kcal, P/C/F macro dots, new-entry emphasis, and low-confidence/needs-review indicator. [analyze clean; on-device smoke pending]
- [x] 4.3 Entry `⋯` menu expands to Edit / Save / Wrong / Delete (≥44px targets). Delete shows a SnackBar with an **Undo** action backed by `restoreChatMessage` (see §1.3). [analyze clean; on-device smoke pending]
- [x] 4.4 Empty state: "Log food or exercise below" (today) / "Nothing logged" (past day). Verify grouping, subtotals, and each menu action on a seeded day. [analyze clean; on-device smoke pending]

## 5. Logging composer sheet

- [x] 5.1 Build `log_composer_sheet.dart` bottom-sheet: compose → analyzing → committed (parseChat commits atomically, no in-sheet estimate/cart preview per design D3); pinned "Log a meal or exercise…" bar opens it. [analyze clean; on-device smoke pending]
- [x] 5.2 Compose phase: text input (autofocus) + quick-add chips + autosuggest; submit → analyzing indicator; error state on failure (retry inline; entry review is post-log via Edit/Wrong). [analyze clean; on-device smoke pending]
- [ ] 5.3 Estimate phase — SUPERSEDED by design D3: parseChat commits atomically via the chat path (no in-sheet estimate → Log it). Review is post-log via the entry's Edit/Wrong. Not built by design.
- [ ] 5.4 Edit-from-entry — the card's Edit is INLINE (`_FoodEditField` + `editAllChatFoodItems`) per the entry-card spec, not a composer re-open. Not built as a composer flow by design.
- [x] 5.5 First-run gate: when neither cloud nor on-device AI is available (and not skipped within cool-down), opening the composer first shows the "Set up smart logging" modal. [analyze clean; on-device smoke pending]

## 6. Photo logging & remaining sheets (More.dc.html style)

- [x] 6.1 Restyle `food_photo_sheet.dart`: source (Take photo / Choose from gallery) → preview (photo + note + Retake/Analyze). The reference "estimate" step maps to the committed log entry — `parsePhoto` commits atomically (no in-sheet preview), preserving `photoAi` attribution + no auto-learn. Retake loops back to the source picker. [analyze clean; on-device smoke pending]
- [ ] 6.2 First-run "Set up smart logging" modal restyled (on-device/cloud option rows + Download AI / Skip) in the composer. Save-as-template kept as the existing name dialog (full reference sheet not yet ported).
- [ ] 6.3 Verify photo capture → estimate → log, save-as-template round-trip, and first-run download/skip on-device.

## 7. Header, exercise, theming & finish

- [x] 7.1 Header: "Nutrition" title + Cloud/Local pill (from AI-tier state) + history + library (+ settings) controls + conditional back control; kept week arrows + month picker on the date strip. [analyze clean; on-device smoke pending]
- [x] 7.2 Ensure exercise entries render as log entries (activity name, stats, −burned kcal) and update the hero's burned value (via `selectedDateCaloriesBurned`). [analyze clean; on-device smoke pending]
- [ ] 7.3 Light/dark pass: confirm all new widgets read `Theme.of(context)`/`context.appColors`, Material icons only, no hardcoded `AppColors*` in widgets; check contrast in both themes.
- [ ] 7.4 `dart format` + `flutter analyze` clean; run the nutrition test suite; on-device eyes-on smoke of the full feature-parity checklist (design.md). Open PR to `dev`.
