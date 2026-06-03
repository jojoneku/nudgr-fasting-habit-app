# Plan 036 — Decomposition: NutritionPresenter & NutritionScreen God Classes

> **Status:** Implementation plan. Executes Plan 035 findings **A1** (presenter god class) and **A3** (screen god class), and directly unblocks **C2/C3** (testability).
> **Severity of domain:** 🟠 Medium — maintainability/testability. No user-facing behaviour should change; this is a structure-only refactor.
> **One-sentence summary:** Break the 2741-line `NutritionPresenter` into a thin orchestrator + three focused collaborators (a pure body-comp calculator, a stateless food resolver, a chat-log sub-presenter), then split the 39-class `nutrition_screen.dart` into folders — all behind the existing public API so views and tests never change.

---

## Guiding constraints (read first)

1. **The public API is frozen.** ~95 presenter members are consumed across `lib/views/nutrition/**`. The decomposition uses a **facade + delegation** pattern: `NutritionPresenter` keeps every public getter/method signature and *delegates* to the extracted collaborators internally. No view file changes in A1.
2. **Behaviour is frozen.** This is a pure refactor. The two existing test suites — `nutrition_presenter_test.dart` (23 tests) and `food_logging_pipeline_test.dart` — must stay green **without edits** after every phase. If a test needs editing, the refactor changed behaviour: stop and reassess.
3. **One extraction = one commit = one PR**, in the order below. Each phase ends with a green checkpoint (`flutter test && dart analyze && dart format`). Never bundle two extractions (per the repo's one-PR-per-change rule).
4. **Dependency direction:** collaborators never import the presenter. Where a collaborator must write back (chat → daily log), it depends on a **narrow callback interface**, not the god class.

---

## Current responsibility map (`nutrition_presenter.dart`, 2741 lines)

| # | Responsibility | Approx. members | Disposition |
|---|---|---|---|
| 1 | Core nutrition state (todayLog, goals, history, tdee, calorie getters) | `:133-360` | **Stays** in presenter (orchestrator core) |
| 2 | Body-comp & dashboard math (weight/waist/bodyfat trends, `dashboardStatus`, `_cutStatus`/`_leanGainStatus`/`_recompStatus`/`_maintainStatus`, KPI/trend labels, 7-day stats) | `:140-616`, `:375-395` | **→ `BodyCompositionCalculator`** (pure util) — Phase 1 |
| 3 | Food resolution (DB/FTS/hybrid match, entry building, name formatting) + `_HybridMatch` | `:1117-1294`, `:2715-2728` | **→ `FoodResolver`** (stateless service) — Phase 2 |
| 4 | Chat parse + commit + edit ops, candidate pool, exercise parse, feedback, `_CloudParseResult` | `:1381-2570`, `:2730-2741` | **→ `ChatLogController`** (sub-presenter) — Phase 3 |
| 5 | Streaks / XP gamification (`_checkGoalMet`, `_updateLogStreak`, `_checkRecompXp`, …) | `:2639-2712`, `:1357-1379` | **Stays** (out of scope; note for a later plan) |
| 6 | Templates, weight/measurement logging, manual entry, AI-estimate (non-chat) | scattered | **Stays** (orchestrator core) |
| 7 | Calorie-density table | — | ✅ Already extracted (Plan 035 A2) |

Target end-state: `NutritionPresenter` ≈ 900–1100 lines (state + orchestration + streaks + templates), with three new testable units beside it.

---

## Phase 1 — `BodyCompositionCalculator` (pure util) · LOWEST RISK

**Why first:** zero mutable state, no `notifyListeners`, no async, no I/O. Pure functions over data lists. Cannot regress the food pipeline. Builds confidence in the delegation pattern.

### New file: `lib/utils/body_composition_calculator.dart`
Static, pure methods taking explicit typed inputs (no presenter reference):

- `double? weightDelta(List<WeightEntry>)`
- `WeightTrendDirection weightTrend(List<WeightEntry>)`
- `double? waistDelta(List<BodyMeasurementEntry>)`
- `MeasurementTrendDirection waistTrend(List<BodyMeasurementEntry>)`
- `({double? navy, double? bmi}) bodyFatEstimates(...)` and `double? estimatedBodyFatPercent(...)`
- `List<({DateTime date, double bf})> bodyFatHistory(...)`
- `int sevenDayAvg(List<DailyNutritionLog>)`, `double? proteinHitRate7d(...)`, `double loggingConsistency7d(...)`
- `DashboardStatus dashboardStatus({required List<DailyNutritionLog> history, TdeeProfile? profile, required NutritionGoals goals, required List<WeightEntry> weightLog, required List<BodyMeasurementEntry> measurementLog})` — absorbs the four private `_*Status` helpers as private top-level functions in the same file.
- Label helpers: `primaryKpiLabel`, `secondaryKpiLabel`, `weightTrendLabel`, `waistTotalChangeLabel`, `bodyFatRangeLabel` (these take `activeGoal`/data as args).

### Presenter change
Each former getter becomes a one-line delegate, e.g.:
```dart
DashboardStatus get dashboardStatus => BodyCompositionCalculator.dashboardStatus(
      history: _history, profile: _tdeeProfile, goals: _goals,
      weightLog: _weightLog, measurementLog: _measurementLog,
    );
```
Keep the unit-conversion getters (`formatMeasurement`, `toStorageCm`) in the presenter only if they read `_measurementUnit` state — or pass the unit in. Recommend: move the pure conversion math to the calculator, keep the stateful wrapper in the presenter.

### Tests
New `test/utils/body_composition_calculator_test.dart`: cut/bulk/recomp/maintain status branches, the recomp-confirmation path (stable weight + waist down), trend thresholds, insufficient-data guards. This is the first time this math is unit-tested in isolation (Plan 035 C2).

### Checkpoint
`flutter test && dart analyze && dart format` — existing presenter tests unchanged.

---

## Phase 2 — `FoodResolver` (stateless service) · MEDIUM RISK

**Why second:** `ChatLogController` (Phase 3) depends on it, so it must land first. Stateless (no `notifyListeners`), so safe to extract before the stateful chat controller.

### Pre-step: extract shared name formatter
`_formatDisplayName` (`:1262`) is used by resolution **and** chat. Move it to `lib/utils/food_name_formatter.dart` as `String formatFoodDisplayName(String)` (Plan 035 E2). Update both call sites. Tiny, do-it-first sub-commit within this phase.

### New file: `lib/services/food_resolver.dart`
Constructor-injected deps: `FoodDbService`, `AiCoachService` (for the semantic channel), `PersonalFoodDictionary`. Methods moved verbatim (logic unchanged):
- `Future<List<FoodDbEntry?>> resolveDbMatches(FoodParseResult)`
- `Future<_HybridMatch?> hybridResolveItem({required String name})` → make `HybridMatch` public (move the class here)
- `Future<FoodDbEntry?> resolveOneDbItem(...)`, `resolveViaFts5(...)`
- `FoodEntry buildEntry(ParsedFoodItem, FoodDbEntry?)` (uses `cde.*` + formatter)
- `FoodEntry buildEntryFromDict(ParsedFoodItem, PersonalFoodEntry)`

`buildEntry`’s keyword-fallback branch already calls the Plan-035-A2 `cde.*` functions — keep those calls.

### Presenter / wiring
- Presenter constructs `FoodResolver` once in its constructor and stores it.
- `parseMeal` / `confirmParsedMeal` / `parseFoodItemsForTemplate` delegate to `_resolver`.
- `_parsedDbMatches` **state stays in the presenter** (it's parse-session UI state); only the *computation* moves.

### Tests
- `food_logging_pipeline_test.dart` must stay green untouched — it's the safety net for this phase.
- Add `test/services/food_resolver_test.dart` for `buildEntry` fallback tiers and `hybridResolveItem` confidence-gap scoring (now isolatable).

### Checkpoint
Full suite green; no view edits.

---

## Phase 3 — `ChatLogController` (sub-presenter) · HIGHEST RISK

**Why last:** owns mutable, listenable state and the cross-cutting commit path that mutates the daily log. Depends on Phase 2’s `FoodResolver`.

### New file: `lib/presenters/chat_log_controller.dart` — `ChangeNotifier with SafeNotifier`
**Owns state:** `_chatMessages`, `_isChatParsing`, `_chatParseError`, `_selectedDate`, `_feedback` (+ `_CloudParseResult` moves here as a private class).

**Methods moved (logic unchanged):** `parseChat`, `_parseChatAsFood`, `_tryLocalParseFood`, `_tryCloudParseFood`, `_combineEntriesAsOneDish`, `_splitForCandidateRetrieval`, `_buildCandidatePool`, `_commitFoodChat`, `_parseChatAsExercise`, `swapChatFoodAlternative`, `markChatMessageDisliked`, `removeChatFoodItemAt`, `removeChatMessage`, `editChatFoodItem`, `editAllChatFoodItems`, `_persistChatMessages`, `_logFeedback`, `_learnFromEntry`, `setSelectedDate`, the selected-date calorie getters.

**Injected deps:** `FoodResolver`, `FoodDbService`, `AiCoachService _ai`, `AiCoachService? _cloudAi`, `PersonalFoodDictionary`, `StorageService`, `StatsPresenter` (for `_learnFromEntry` XP), and a **narrow write-back interface** (below).

### The coupling solution — a narrow callback interface
Committing chat food mutates `_todayLog` (presenter-owned, drives calorie getters). Do **not** hand the controller the whole presenter. Define:
```dart
abstract class FoodLogSink {
  Future<void> commitChatEntries(List<FoodEntry> entries, DateTime date);
  DailyNutritionLog logForDate(DateTime date);
}
```
`NutritionPresenter implements FoodLogSink`. Controller calls `_sink.commitChatEntries(...)`. Dependency points controller → interface, never controller → god class.

### Notifications — preserve the public API
Views currently listen to the presenter and read `presenter.chatMessages`, `presenter.isChatParsing`, etc. Two-part bridge:
1. Presenter constructs `_chat = ChatLogController(...)` and does `_chat.addListener(safeNotify)` so any chat change still notifies presenter listeners (existing views need no change).
2. Presenter keeps delegating getters/methods: `List<ChatMessage> get chatMessages => _chat.chatMessages;`, `Future<void> parseChat(String t) => _chat.parseChat(t);`, etc.
3. `dispose()`: presenter removes the listener and disposes `_chat`.

> **Optional follow-up (separate PR, A3-adjacent):** once stable, change `_ChatFeed`/`_ChatInputBar` to listen to the controller directly via an `InheritedNotifier`, dropping the re-broadcast. Not required for this plan.

### Tests
- All chat-related cases in the existing suites stay green untouched.
- New `test/presenters/chat_log_controller_test.dart`: tier fall-through (cloud→local→keyword), single-dish vs items-list intent, edit/remove/swap ops, feedback logging, commit-to-sink via a fake `FoodLogSink`.

### Checkpoint
Full suite green; manual smoke test of the chat-logging flow in the running app (`/run`) — highest-risk path, verify by hand.

---

## Phase 4 (optional, separate PRs) — A3 screen split

`nutrition_screen.dart` (2448 lines, **39 widget classes**) — file decomposition only, no logic change. Split by feature folder; move classes verbatim, fix imports:

- `lib/views/nutrition/header/` → `_WeekStrip`, `_StatSection`, `_StatCell`, `_ColDivider`, `_AiTierBadge`, `_MonthPicker`
- `lib/views/nutrition/chat/` → `_ChatFeed`, `_ChatMessageCard`, `_FoodAnalysisCard`, `_FoodItemRow`, `_FoodEditField`, `_AlternativesStrip`, `_AlternativeChip`, `_MealTotalRow`, `_FoodItemDisplay`, `_ExerciseAnalysisCard`, `_MessageFooter`, `_ChatInputBar`, `_ThinkingBubble`, `_ErrorBubble`, `_EmptyChatState`, `_FirstRunAiPrompt`, badges
- `lib/views/nutrition/detail/` → `_NutritionDetailBody`, `_DetailRow`
- `lib/views/nutrition/tabs/` → `_TemplateBody`, `_ManualFoodBody`
- `nutrition_screen.dart` keeps `NutritionScreen` + `_NutritionBody` shell.

Do this **one folder per PR** to keep diffs reviewable. Same treatment later for `log_meal_sheet.dart` (1762) and `measurement_log_screen.dart` (1715) when next touched.

---

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Hidden read of presenter field inside a moved method | Compiler catches it — moved methods can't see private presenter fields. Pass as params or inject. |
| Memoized template caches cleared on `safeNotify()` | Caches stay in presenter; controller’s `safeNotify` re-broadcasts via the listener bridge, so cache invalidation still fires. |
| Chat commit ordering (commit → recompute calories → notify) | `FoodLogSink.commitChatEntries` runs the *same* sequence the presenter does today; controller awaits it before notifying. |
| `_learnFromEntry` auto-promotion semantics (Plan 033 H2) | Move verbatim; the cloud-fallback guard added in Plan 034 is in the entry-build path (FoodResolver/presenter), unaffected. |
| Test suite needs edits | That signals a behaviour change — **halt** and diff against `main` before proceeding. |

---

## Remediation / execution order
1. **Phase 1** — `BodyCompositionCalculator` + tests. (Smallest, safest; validates the pattern.)
2. **Phase 2** — `food_name_formatter` util, then `FoodResolver` + tests.
3. **Phase 3** — `ChatLogController` + `FoodLogSink` + tests + manual smoke test.
4. **Phase 4** — screen folder splits, one folder per PR (optional / as-touched).

## Definition of done
- `NutritionPresenter` orchestrates only: body-comp math, food resolution, and chat state live in their own constructor-injected, individually-tested units.
- Every existing test passes **unedited** after each phase.
- New unit tests exist for `BodyCompositionCalculator`, `FoodResolver`, and `ChatLogController` (satisfies Plan 035 C2 for the extracted pieces).
- No view file changes in Phases 1–3; the public presenter API is byte-for-byte source-compatible.
- `nutrition_screen.dart` (Phase 4) reduced to the screen shell + per-feature widget folders.
```
