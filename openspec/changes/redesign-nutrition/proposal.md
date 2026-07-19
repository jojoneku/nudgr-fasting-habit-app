## Why

The Nutrition screen is the highest-touch surface in the app after the Hub, and it's the next
screen in the Nudgr redesign. Today it renders as a **chat feed** — user-typed messages as bubbles
with AI-analysis cards threaded inline — which reads as a conversation transcript rather than a
day's nutrition record. There's no at-a-glance "how am I doing today," logged items aren't grouped
by meal, and the whole logging flow is entangled with the scrolling feed. The locked-in reference
(`Nutrition Focus Prototype.dc.html` + `Nutrition Focus More.dc.html`) reframes it into a **daily
nutrition dashboard**: an EATEN TODAY hero, a meal-grouped structured log, and a dedicated composer
sheet for logging (typed or photo). This is a **restyle + reframe** that keeps every existing
capability — it re-homes the chat interaction into a composer sheet and turns the feed into a
structured log; it does not remove food/exercise/photo logging, learning, or templates.

## What Changes

- **Reframe the screen body** from a chat-bubble feed to a flat **"Today's log"** — logged items
  rendered as structured entry cards in a single newest-first list for the day (no meal-slot
  grouping), preceded by a section label with the day's total calories.
- **Restyle the calorie/macro summary into the EATEN TODAY hero** — gradient card with big eaten
  kcal, "left of goal" in the domain accent, a calorie progress bar, and P/C/F mini-bar columns.
  Keeps the current card's data (Eaten / Left / **Burned**) and its tap-to-open breakdown sheet.
- **Move conversational logging into a composer bottom-sheet** opened from a pinned
  "Log a meal or exercise…" input bar: draft bubble → "Analyzing…" → estimate card
  (item list + macro totals + **Log it / Edit**), plus quick-add chips. This replaces the inline
  input bar + inline thinking/estimate bubbles.
- **Restyle photo logging** into the reference's source → preview → estimate sheet sequence
  (Take photo / Choose from gallery → note + Retake/Analyze → estimate → Log it/Edit).
- **Per-entry `⋯` menu** expands to **Edit / Save (as template) / Wrong / Delete**, replacing the
  current per-card footer action row. Deletes and logs surface an **Undo toast**.
- **Restyle** the source badges (Cloud / Local / Library), library "save as template" sheet, and the
  first-run **"Set up smart logging"** AI modal to match the reference.
- **Preserve (not in the mockup, must not be removed):** week prev/next arrows + month-picker date
  navigation, **exercise** entries (shown as log entries; input copy is "meal or exercise"),
  low-confidence handling and **alternatives** ("Wrong" → re-match / alternatives), the **Burned**
  stat, per-item edit-in-place, and the on-device/cloud AI tier badge.
- Use **Material icons** (not Phosphor) and read all colors from `Theme.of(context)` /
  `context.appColors`, consistent with the shipped Nudgr tokens (PR #458) and the Hub redesign.

Non-breaking. No presenter, model, service, or navigation entry point is removed; `NutritionScreen`
keeps its constructor and its push sites from the Hub are unchanged.

## Non-goals

- **No presenter/business-logic rewrite.** `NutritionPresenter` / `AiCoachPresenter` keep their
  public API; this change is view-layer + light additive getters only. Food resolution, the RPG/XP
  math, learning into the personal dictionary, and persistence are untouched.
- **No data-model or storage changes**, and no migration — existing logged entries, templates, and
  chat history render in the new structure as-is.
- **Not the History or Library screens.** The reference shows richer History (trend/goal-checks) and
  Library screens; those are captured for a **later** change. This change only restyles the existing
  history/library **entry points** and the save-as-template sheet, not a History/Library rebuild.
- **No new dependencies** (no Phosphor package, no font work — tokens already shipped).
- **Not the web companion** (`TreasuryWebApp` is finance-only; Nutrition is mobile).

## Capabilities

### New Capabilities
- `nutrition`: The Nutrition screen — header (title, AI-tier/Cloud pill, history + library entry
  points), date navigation (week strip + arrows + month picker), the EATEN TODAY hero
  (eaten/left-of-goal/burned + P/C/F, over-goal state, tap-for-breakdown), the flat structured
  "Today's log" with source badges and the per-entry Edit/Save/Wrong/Delete menu, the
  logging composer sheet (typed draft → estimate → Log it/Edit, quick-add chips), photo logging
  (source → preview → estimate), exercise entries, save-as-template, the first-run AI setup prompt,
  undo toasts, and empty/loading/error states — with graceful degradation when the AI-coach
  presenter is absent.

### Modified Capabilities
<!-- None. openspec/specs/ contains only `hub`; there is no existing `nutrition` capability, and no
     other capability's spec-level requirements change. Presenter additions are implementation
     details covered in design.md. -->

## Impact

- **New:** likely `lib/views/nutrition/widgets/` for extracted pieces — `eaten_today_hero.dart`,
  `nutrition_log_list.dart` (meal grouping + entry card + `⋯` menu), `log_composer_sheet.dart`
  (draft/analyzing/estimate + quick chips), and photo capture sheet restyles.
- **Modified:** `lib/views/nutrition/nutrition_screen.dart` (feed → hero + log list + pinned bar),
  `food_photo_sheet.dart` (source/preview/estimate restyle), `add_food_sheet.dart` /
  `nutrition_settings_sheet.dart` (composer + first-run modal restyle as needed),
  `food_library_screen.dart` save-as-template sheet.
- **Presenter (additive only):** small computed getters on `NutritionPresenter` for meal grouping,
  "left of goal", and macro percentages if not already present — no behavior change to existing
  getters.
- **Reuses (unchanged):** `NutritionPresenter`, `AiCoachPresenter`, `FoodDbService`, the meal-slot
  model, `AppCard`/`AppLinearProgress`/`AppBottomSheet`/`AppEmptyState` from
  `views/widgets/system/`, Nudgr theme tokens, `StorageService`.
- **Deps:** none new. **Risk:** the composer sheet must fully cover current inline logging
  (edit-in-place, alternatives, photo, exercise, first-run AI) — feature parity is the main risk;
  verified against a capability-mapping checklist in design.md.
