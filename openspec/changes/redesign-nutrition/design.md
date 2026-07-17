## Context

The current `lib/views/nutrition/nutrition_screen.dart` (~2.5k lines) renders a **chat feed**: it
lists `NutritionPresenter.chatMessages` as bubbles, with inline `_FoodAnalysisCard` /
`_ExerciseAnalysisCard` widgets, an inline thinking/error bubble, a pinned `_ChatInputBar`, and a
`_StatSection` calorie/macro card above the feed. The persisted daily food log lives separately in
the presenter as `_todayLog` (a `DailyLog` of `FoodEntry` records keyed by `MealSlot`), and chat
food items reference their persisted `entryId`.

Two model facts constrain the redesign:
1. **`MealSlot.meal` is a universal slot** — `addEntries(...)`/`addFoodEntry(...)` for chat/typed
   logging always write to `MealSlot.meal`. The breakfast/lunch/dinner/snack slots exist in the
   model and in `caloriesForSlot`/`entriesForSlot`, but new entries are not currently bucketed.
2. The **chat layer and the persisted log are linked** — edit/delete/alternatives/dislike currently
   operate through `chatMessage`-scoped presenter methods (`editAllChatFoodItems`,
   `removeChatFoodItemAt`, `swapChatFoodAlternative`, `markChatMessageDisliked`, …), each of which
   mutates `_todayLog` under the hood.

The reference (`Nutrition Focus Prototype.dc.html`, `Nutrition Focus More.dc.html`) shows a daily
dashboard: EATEN TODAY hero → meal-grouped structured "Today's log" → pinned input bar → composer
sheet; plus photo source/preview/estimate sheets, a save-as-template sheet, and a first-run AI modal.

## Goals / Non-Goals

**Goals:**
- Reframe the screen body from a chat feed to a **meal-grouped structured log** rendered from the
  **persisted `_todayLog`**, matching the reference's visual language via existing Nudgr theme tokens.
- Restyle the calorie/macro card into the **EATEN TODAY hero** while keeping its data
  (Eaten / Left / Burned + P/C/F) and its tap-to-open breakdown behavior.
- Re-home conversational logging into a **composer bottom-sheet** (draft → analyzing → estimate →
  Log it/Edit + quick chips) that wraps the existing analysis pipeline.
- Restyle photo logging, save-as-template, and the first-run AI prompt per the reference.
- Preserve 100% of current capability (feature-parity checklist below).

**Non-Goals:**
- No change to `NutritionPresenter` / `AiCoachPresenter` public behavior, food resolution, RPG/XP
  math, learning, or persistence — additions are thin, additive, read-only getters.
- No data-model / storage change and no migration.
- Not a History/Library **rebuild** (only the entry points + save-as-template sheet are restyled).
- No new packages, no Phosphor, no font work.

## Decisions

### D1 — Render the log from persisted `_todayLog`, not `chatMessages`
The "Today's log" list is built from the day's persisted `FoodEntry` records (and exercise
entries), so it is a true daily record independent of ephemeral chat state.
- *Why:* the reference is a log, not a transcript; persisted entries survive app restarts and match
  the hero totals exactly.
- *Alternative rejected:* keep rendering `chatMessages` — leaks conversational artifacts into a
  "record" view and breaks on history days with no chat.
- *Consequence:* per-entry actions bind to **entry-level** presenter methods. Where only
  chat-scoped methods exist today, add thin entry-id-keyed shims that reuse the same internal
  mutation paths (no new business logic).

### D2 — Flat "Today's log", no meal-slot grouping
Render the day's entries as a single flat list ordered newest-first, with no Breakfast/Lunch/
Dinner/Snack section headers. A presenter getter returns the day's entries in display order.
- *Why:* explicit product decision — no meal slots. Also the simplest match to the persisted model,
  where new entries all land in the universal `MealSlot.meal`; a flat list needs no inference and no
  model change. Matches the prototype HTML's flat `Today's log`.
- *Alternatives rejected:* (a) meal-slot grouping by time-of-day inference; (b) composer meal-slot
  tabs that persist a slot. Both add meal-slot concepts the product does not want.

### D3 — Composer sheet wraps the existing analysis pipeline
The composer is a stateful bottom-sheet with phases compose → analyzing → estimate, driven by the
presenter's existing parse/analyze/commit methods. "Log it" commits to `_todayLog`; "Edit" returns
to an editable state. Edit-from-entry (D1) opens the composer pre-filled and commits as a replace.
- *Why:* reuse the proven resolution/learning pipeline; only the presentation moves.
- *Consequence:* the inline `_FoodAnalysisCard` edit/alternatives/dislike affordances are relocated —
  estimate-time editing + alternatives live in the composer; post-log Edit/Wrong live in the entry
  `⋯` menu.

### D4 — Widget extraction
Break the monolith into `lib/views/nutrition/widgets/`: `eaten_today_hero.dart`,
`nutrition_log_list.dart` (meal groups + `_LogEntryCard` + `⋯` menu), `log_composer_sheet.dart`,
and restyled photo sheets. `nutrition_screen.dart` becomes a thin scaffold assembling them.
- *Why:* the 2.5k-line file is unmaintainable and mixing concerns; extraction keeps `build()`
  logic-free per the architecture rules.

### D5 — Material icons + theme tokens only
Map Phosphor glyphs in the reference to Material equivalents (ph-cloud → `Icons.cloud_outlined`,
ph-camera → `Icons.photo_camera_outlined`, ph-dots-three → `Icons.more_horiz`, ph-sparkle →
`Icons.auto_awesome`, ph-bookmark-simple → `Icons.bookmark_outline`, ph-thumbs-down →
`Icons.thumb_down_outlined`, ph-pencil-simple → `Icons.edit_outlined`, ph-trash →
`Icons.delete_outline`). All colors via `Theme.of(context)` / `context.appColors`.
- *Why:* consistent with the Hub redesign and CLAUDE.md theme rule; no new dependency.

### Feature-parity checklist (current → new home)
| Current (chat feed) | New home |
|---|---|
| Calorie/macro `_StatSection` + breakdown sheet | EATEN TODAY hero (tap → same breakdown sheet) |
| Food analysis card | Log entry card (from `_todayLog`) |
| Inline input bar + thinking/estimate bubbles | Pinned bar → composer sheet (analyzing/estimate) |
| Edit-in-place (`editAllChatFoodItems`) | Composer Edit (entry `⋯` → Edit → composer) |
| Alternatives strip (`swapChatFoodAlternative`) | Composer estimate alternatives / entry `⋯` → Wrong |
| Save as template | Entry `⋯` → Save → save-as-template sheet |
| Dislike (`markChatMessageDisliked`) | Entry `⋯` → Wrong |
| Photo logging (`food_photo_sheet.dart`) | Composer camera → source/preview/estimate sheets |
| Exercise analysis card | Exercise log entry (burned kcal) |
| Empty / thinking / error states | Empty-day state / composer analyzing / composer error |
| First-run AI prompt | "Set up smart logging" modal (More.dc.html style) |
| AI tier badge, week nav + month picker, Burned | Preserved (header pill, date strip, hero/breakdown) |

## Risks / Trade-offs

- **Feature-parity regression (highest risk):** the composer must fully replace inline logging,
  including edit-in-place, alternatives, photo, exercise, and first-run AI. → Mitigation: implement
  against the checklist above; keep the presenter pipeline unchanged; verify each row on-device
  before PR (mobile app can't be driven in this environment — eyes-on smoke required).
- **Chat ↔ entry coupling:** entry-level actions may need shims over chat-scoped methods. →
  Mitigation: shims reuse the same internal `_todayLog` mutation paths; no new resolution logic; add
  unit coverage for any new getter/shim. Do NOT regenerate `test/mocks.mocks.dart` (breaks finance
  suites) — hand-fake collaborators.
- **Large view refactor churn:** extracting a 2.5k-line file risks behavioral drift. → Mitigation:
  move widgets with minimal edits first, restyle second; keep presenter calls identical.

## Migration Plan

View-layer only; no data migration. Ship on a feature branch off `dev` (`feat/redesign-nutrition`),
`dart format` + `flutter analyze` clean, PR targets `dev` (one PR). Rollback = revert the PR; no
persisted-state implications. Existing logged entries/templates/history render immediately in the
new structure.

## Open Questions

- **Alternatives placement:** show runner-up matches inside the composer estimate card, in the entry
  `⋯` → Wrong flow, or both? Proposed: estimate card at log time; `⋯` → Wrong post-log.
- **History/Library depth:** the reference's richer History (trend, goal-checks, KPI tiles) and
  Library (search, meals/foods/recent tabs) are separate changes — confirm they are out of scope here.
