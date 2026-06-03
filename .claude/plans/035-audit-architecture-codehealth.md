# Plan 035 — Audit: Architecture & Code Health

> **Status:** Audit findings + remediation plan.
> **Severity of domain:** 🟡 Medium — these are maintainability and testability risks, not user-facing crashes. They compound the *cost* of every other fix in Plans 030–034.
> **One-sentence summary:** The MVP layering is mostly respected, but two god classes (nutrition presenter/screen) concentrate disproportionate risk, one global singleton breaks the DI rule, and the riskiest code (sync) is the thinnest-tested.

---

## Findings

### 🟠 A1 — `nutrition_presenter.dart` is a 7-in-1 god class (3115 lines)
- **Where:** `lib/presenters/nutrition_presenter.dart:37-3115`.
- **Problem:** Mixes ≥7 responsibilities: body-composition status math (`:662-820`), rule-based food NLP + DB resolution (`:1327-1435`), cloud AI parsing with post-processing guards (`:2044-2245`), the chat state machine (`:1728-2944`), weight/measurement logging, templates, and XP/streak gamification. Every food-logging change risks regressing fasting XP or body-comp UI; untestable as a unit; merge-conflict-prone.
- **Fix:** Extract `FoodResolver`/`FoodParsingService` (DB/NLP/cloud resolution, ~`:1327-2350`), a pure `BodyCompositionCalculator` util (the status methods), and a `ChatLogController` sub-presenter. The presenter should orchestrate, not implement.

### 🟠 A2 — ~200-line calorie-density domain table embedded in the presenter
- **Where:** `nutrition_presenter.dart:78-294` (`_calorieBuckets`).
- **Problem:** A static keyword→kcal/g lookup table + fallback logic — pure reference data + pure function — living in the presenter, violating the Utils/Presenter layering in CLAUDE.md. Data edits force presenter recompiles; can't be unit-tested or reused.
- **Fix:** Move to `lib/utils/calorie_density_estimator.dart` as `double estimateKcalPerGram(String name)`. (Pairs with Plan 033 H1 — give each bucket a macro profile while you're there.)

### 🟡 A3 — `nutrition_screen.dart` is a 38-class kitchen-sink file (2435 lines)
- **Where:** `nutrition_screen.dart:21-2282`.
- **Problem:** Poor file decomposition (not individually huge `build()`s) — `_WeekStrip`, `_ChatFeed`, `_FoodAnalysisCard`, `_ChatInputBar`, `_TemplateBody`, `_ManualFoodBody`, `_MonthPicker`, etc. all in one file. IDE/navigation drag, ownership ambiguity, review friction.
- **Fix:** Split into `nutrition/chat/`, `nutrition/header/`, `nutrition/sheets/`. `log_meal_sheet.dart` (1762) and `measurement_log_screen.dart` (1715) deserve the same.

### 🟠 B1 — `AuthService` is a global singleton locator (breaks DI rule 6)
- **Where:** `lib/services/auth_service.dart:8` (`static final AuthService instance`), consumed in `home_screen.dart:91,131,148`.
- **Problem:** CLAUDE.md rule 6 mandates constructor injection only, no global locators. This is the one place the otherwise-clean DI graph leaks — untestable auth (can't inject a fake), hidden global state.
- **Fix:** Instantiate `AuthService` once in `_AppShellState.initState` and inject it like every other service; delete the static `instance`.

### 🟡 B2 — `_AppShellState` is an 18-presenter manual composition root with load-bearing init order
- **Where:** `home_screen.dart:47-181` (init `:72-158`, dispose `:160-181`; ledger-before-treasury/budget/bills ordering `:101-112`).
- **Problem:** Acceptable for "no GetIt", but brittle — adding a presenter means touching fields + init + dispose, and any missed `dispose()` leaks. Order is implicit, not enforced.
- **Fix:** Introduce a single `AppDependencies` container that builds the graph and exposes `dispose()`, keeping constructor injection but centralizing lifecycle. Lower priority than the crash bugs in Plan 031.

### 🟡 B3 — Hidden cross-layer coupling via mutable storage callbacks
- **Where:** `local_storage_service.dart:44-62` — public mutable `VoidCallback? onRemoteDataApplied` / `onDirty`, wired from `home_screen.dart:197-198`.
- **Problem:** The storage layer calls *up* into sync orchestration — an implicit event bus that inverts the layering and obscures who reloads when.
- **Fix:** Model it as a proper `Stream`/listener interface or inject a `SyncCoordinator` dependency.

### 🟠 C1 — Sync stack is the riskiest code and is thinly covered
- **Where:** `sync_service.dart` (743 lines) — conflict resolution / last-writer-wins (`:377,434,476,515`), once-per-device push guard (`:712`). `_initSync` failure path (Plan 031 H1) untested.
- **Fix:** Add conflict-resolution cases (remote-newer, local-newer, missing-row, partial-push-failure recovery) and a failure-recovery test.

### 🟡 C2 — Largest presenter under-tested relative to size
- **Where:** `nutrition_presenter_test.dart` (281 lines / 23 tests) + `food_logging_pipeline_test.dart` (687 lines) for a 3115-line class. The food pipeline is well-covered; body-comp status math, XP/streak triggers, and chat-edit ops are light. Extracting per A1/A2 makes these unit-testable.

### 🟡 C3 — Untested presenters/services
- `ai_coach_presenter` (highest priority — has the dispose/streaming crash in Plan 031 C2), `installment_presenter`, `hub_presenter`, `sync_presenter`, `update_presenter`, `settings_presenter`. (Treasury/ledger/budget/bills *are* covered via `treasury_presenters_test.dart`; storage via `storage_service_test.dart`.)

### 🟡 D1 — Silently swallowed deserialization → undiagnosable data loss
- **Where:** `local_storage_service.dart:151`, `sync_queue.dart:34,43` (`catch (_) {}`). *(Detailed in Plan 031 M1; lives there for remediation.)*

### 🟢 Low — duplication / trapped utilities
- **E1:** Two near-identical learn-from-corrections services — `personal_food_dictionary.dart` (146) and `finance_personal_dictionary.dart` (115). Shareable via a generic `PersonalDictionary<T>` on the next touch.
- **E2:** `_formatDisplayName` (`:1481`) and `_calorieBuckets` (`:78`) are the only implementations (no live duplication) but are trapped in the presenter — pull into utils when extracting per A1/A2 so the food-library and template screens can reuse them.

---

## Remediation order
1. **B1** — remove the `AuthService.instance` singleton (small, restores the DI rule, unblocks auth testing — needed for Plan 030 work anyway).
2. **A2** — extract the calorie-density table to a pure util (small, unblocks Plan 033 H1).
3. **A1** — break up `nutrition_presenter.dart` into `FoodResolver` + `BodyCompositionCalculator` + `ChatLogController`; add unit tests to the extracted pieces.
4. **C1** — add sync conflict + failure-recovery tests (do alongside Plan 030/031 sync fixes).
5. **A3, B2, B3, C2, C3, E1/E2** — incremental as those files are touched.

## Definition of done
- No global service locators; all services constructor-injected.
- `nutrition_presenter.dart` orchestrates; resolution, body-comp math, and chat state live in their own testable units.
- Sync conflict resolution and failure recovery have explicit tests.
- `ai_coach_presenter` has tests covering the dispose/stream-cancel path.
