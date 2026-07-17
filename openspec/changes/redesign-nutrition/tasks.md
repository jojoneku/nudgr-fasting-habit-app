## 1. Presenter & util groundwork (land before UI)

- [ ] 1.1 Add a read-only `NutritionPresenter` getter returning the selected day's food entries as a single flat list ordered newest-first (no meal-slot grouping), plus the day's total kcal. Reuse existing `_todayLog` accessors; unit-test ordering + total.
- [ ] 1.2 Add read-only hero getters if missing: eaten kcal, left-of-goal (vs `effectiveGoal`), calorie progress, `isOverGoal`, per-macro grams + progress, burned kcal. Reuse existing getters where present; unit-test any new one.
- [ ] 1.3 Add thin entry-level action shims keyed by `FoodEntry.id` for Edit / Delete(+undo) / Wrong(dislike) / Save-as-template that reuse existing internal `_todayLog` mutation paths (no new resolution logic). Unit-test delete+undo and save-as-template. Do NOT regenerate `test/mocks.mocks.dart` — hand-fake collaborators.

## 2. Shared widget extraction (no visual change yet)

- [ ] 2.1 Create `lib/views/nutrition/widgets/` and move the calorie/macro card, log rendering, and input bar out of `nutrition_screen.dart` into stub widgets with identical behavior; confirm `flutter analyze` clean and existing tests green.
- [ ] 2.2 Reduce `nutrition_screen.dart` to a thin scaffold (header + date strip + body + pinned bar) delegating to the extracted widgets; no logic in `build()`.

## 3. EATEN TODAY hero (restyle of the stat card)

- [ ] 3.1 Build `eaten_today_hero.dart` — gradient card: "EATEN TODAY" label, big eaten kcal, left-of-goal in the domain accent, calorie progress bar, P/C/F columns with mini-bars. Theme tokens only; Material icons.
- [ ] 3.2 Wire over-goal state (danger color) and keep tap → existing breakdown sheet (which still shows Burned + per-macro detail). Verify under/over-goal and tap-through.

## 4. Today's log (flat list)

- [ ] 4.1 Build `nutrition_log_list.dart` rendering the presenter's flat entry list (§1.1): "Today's log" label + day total kcal, then `_LogEntryCard`s newest-first — no meal-slot section headers.
- [ ] 4.2 `_LogEntryCard`: name, sub-line (amount/grams · time), source badge (Cloud/Local/Library), kcal, P/C/F macro dots, new-entry emphasis, and low-confidence/needs-review indicator.
- [ ] 4.3 Entry `⋯` menu expands to Edit / Save / Wrong / Delete (≥44px targets); wire to the §1.3 shims; Delete shows an undo toast that restores the entry.
- [ ] 4.4 Empty state: "Log food or exercise below" (today) / "Nothing logged" (past day). Verify grouping, subtotals, and each menu action on a seeded day.

## 5. Logging composer sheet

- [ ] 5.1 Build `log_composer_sheet.dart` bottom-sheet with phases compose → analyzing → estimate, driven by the existing analysis pipeline; pinned "Log a meal or exercise…" bar opens it.
- [ ] 5.2 Compose phase: text input (autofocus) + quick-add chips; submit → analyzing indicator; error state on failure with retry/edit.
- [ ] 5.3 Estimate phase: item list + P/C/F/kcal totals + "Log it" / "Edit"; "Log it" commits to `_todayLog` (selected day) and closes with an undo toast; "Edit" returns to editable state; surface alternatives for low-confidence items.
- [ ] 5.4 Edit-from-entry: `⋯` → Edit opens the composer pre-filled and commits as a replace (not a new entry). Verify add, edit-replace, quick-chip, and undo end-to-end.
- [ ] 5.5 First-run gate: when neither cloud nor on-device AI is available (and not skipped within cool-down), opening the composer first shows the "Set up smart logging" modal.

## 6. Photo logging & remaining sheets (More.dc.html style)

- [ ] 6.1 Restyle `food_photo_sheet.dart` into source → preview → estimate sheets: source (Take photo / Choose from gallery), preview (photo + optional note + Retake/Analyze), estimate (items + totals + Log it/Edit). Keep `photoAi` source attribution and no auto-learn.
- [ ] 6.2 Restyle the save-as-template sheet (template name + included items + total + Cancel/Save) and the first-run "Set up smart logging" modal (on-device/cloud options + Download AI / Skip for now) to match the reference.
- [ ] 6.3 Verify photo capture → estimate → log, save-as-template round-trip, and first-run download/skip on-device.

## 7. Header, exercise, theming & finish

- [ ] 7.1 Header: "Nutrition" title + Cloud/Local pill (from AI-tier state) + history + library controls + conditional back control; keep week arrows + month picker on the date strip.
- [ ] 7.2 Ensure exercise entries render as log entries (activity name, stats, −burned kcal) and update the hero's burned value.
- [ ] 7.3 Light/dark pass: confirm all new widgets read `Theme.of(context)`/`context.appColors`, Material icons only, no hardcoded `AppColors*` in widgets; check contrast in both themes.
- [ ] 7.4 `dart format` + `flutter analyze` clean; run the nutrition test suite; on-device eyes-on smoke of the full feature-parity checklist (design.md). Open PR to `dev`.
