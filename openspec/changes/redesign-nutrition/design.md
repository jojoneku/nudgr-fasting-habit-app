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

### D1 — Render the log from `chatMessages` (restyle, not re-source)
The "Today's log" list is built from `NutritionPresenter.chatMessages` — each message is one logged
food entry/meal (or exercise) — restyled from a chat bubble into a structured entry card. This is a
**presentation** change, not a data-source change.
- *Why (revised during implementation):* `chatMessages` already IS the per-entry model that carries
  the display metadata the reference card needs — name/raw text, per-item macros, estimation
  **source** (Cloud/Local/Library), **alternatives**, `needsConfirmation`, photo thumbnail, and
  exercise details — and it is persisted and kept in sync with `_todayLog` via
  `_reconcileChatWithLog`. The raw `FoodEntry` records in `_todayLog` do NOT carry source/
  alternatives/photo, so rendering from them would drop capability.
- *Consequence:* per-entry actions bind to the existing **message-keyed** presenter methods
  (`removeChatMessage`, `markChatMessageDisliked`, `saveFoodTemplate`, `editAllChatFoodItems`, …) —
  no new business logic and no shims needed. Newest-first ordering is a thin presenter getter over
  `chatMessages`. History days with no chat simply show the empty state.
- *Alternative rejected:* re-source from `_todayLog` — loses source/alternatives/photo metadata and
  forces duplicating the edit/delete/learn plumbing.

### D2 — Flat "Today's log", no meal-slot grouping
Render the day's entries as a single flat list ordered newest-first, with no Breakfast/Lunch/
Dinner/Snack section headers. A presenter getter returns the day's entries in display order.
- *Why:* explicit product decision — no meal slots. Also the simplest match to the persisted model,
  where new entries all land in the universal `MealSlot.meal`; a flat list needs no inference and no
  model change. Matches the prototype HTML's flat `Today's log`.
- *Alternatives rejected:* (a) meal-slot grouping by time-of-day inference; (b) composer meal-slot
  tabs that persist a slot. Both add meal-slot concepts the product does not want.

### D3 — Composer commits through the chat path (revised during implementation)
The composer is a bottom-sheet opened from the pinned bar; it reuses the current input bar's
behaviors — typed food/exercise via `parseChat`, `addManualFoodEntry`, `addMealFromTemplate`, photo
via `showFoodPhotoSheet` — plus quick-add chips and typed-name autosuggest (superset, per user).
- *Why (revised):* there are **two logging sinks** — `chatMessages` (created by `parseChat` /
  `addManualFoodEntry`; carries source/alternatives/photo/exercise metadata) and `_todayLog` (the
  calorie/macro totals). The estimate/cart methods (`parseMeal`→`confirmParsedMeal`,
  `estimateMeal`→`confirmAiEstimate`, as used by the existing `LogMealSheet`) commit to `_todayLog`
  **without** creating a `ChatMessage`; `_reconcileChatWithLog` only backfills chat rows on
  load/date-change, not immediately. Since the log list (D1) renders `chatMessages` and **exercise
  entries exist only as chat messages** (never in `_todayLog`), the composer must commit via the
  chat path so logged items appear immediately.
- *Trade-off (deviation from reference):* `parseChat` commits atomically, so the reference's
  *in-sheet* "estimate → Log it/Edit" preview is not reproduced without a no-commit preview mode on
  the presenter — explicitly a **non-goal** (no presenter behavior change). Instead: type →
  "Analyzing…" → logged, with an **undo** toast; review/adjust happens via the entry's Edit
  (inline, `editAllChatFoodItems`) and Wrong (`swapChatFoodAlternative` / `markChatMessageDisliked`)
  in the `⋯` menu. Net logging experience is equivalent; the estimate step moves from pre-log to
  post-log. Accepted 2026-07-18.
- *Consequence:* the `LogMealSheet` (estimate/cart, `_todayLog`-only) is **not** adopted as the
  composer — it would desync from the chat-based log list.

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
