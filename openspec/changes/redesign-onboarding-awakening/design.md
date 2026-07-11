## Context

`main.dart → FastingApp → AppShell` (`home_screen.dart`) is the entry path. The only first-run gate
today is a post-frame check in `AppShell.initState`: unauthenticated users get `LoginView.show()`
(Google or "Log in later" guest) and are then dropped on the Hub with a **null** `TdeeProfile`, a
generic `NutritionGoals.initial()` (2,000 kcal simple mode), and a silent 16h fasting default. Real
profile setup lives three taps deep at `nutrition_settings_sheet.dart:395 → TdeeSetupScreen`.

The flow was fully specced in `docs/onboarding_spec.md` + `.claude/plans/043-onboarding-awakening.md`
but never implemented. Verified facts that constrain this design:
- **All TDEE math already exists** as getters on `TdeeProfile` (Mifflin-St Jeor `bmr`, `tdee`,
  `targetCalories`, `suggestedProteinG/FatG/CarbsG`). The wizard adds **zero** math.
- `TdeeSetupScreen` (~778 lines) is already a 4-step body/activity/goal/review wizard — its form
  bodies are the reuse target.
- Goal values are `'cut' | 'maintain' | 'bulk' | 'recomp'` (`bulk` displays as "Lean gain").
- Protocol presets live in `FastingProtocol.all` (`protocol_card.dart`); commit via
  `FastingPresenter.updateFastingGoal(hours)`.
- Guest wiring: `LoginView` "Log in later" pops → `AppShell` runs `_reloadAll()` +
  `_setupWidgetBridge()`. `NotificationService.requestPermissions()` and
  `QuestPresenter.addQuest(Quest)` both exist.

The redesign reference (`Nutrition Focus Onboarding.dc.html`) is this same 9-step flow rendered in
the **Nudgr** language.

## Goals / Non-Goals

**Goals:**
- Implement the 9-step Awakening flow producing a real profile + goals + protocol on day one,
  reusing existing math and the existing guest/sign-in wiring.
- Restyle into Nudgr via **theme-aware tokens only**, so both dark and light modes work.
- Keep the wizard and `TdeeSetupScreen` from drifting by sharing extracted form widgets.
- Make the flow skippable, replayable, and idempotent on one-time effects.

**Non-Goals:**
- Replacing `TdeeSetupScreen` or `LoginView` (both retained).
- Defining the global Nudgr theme (fonts/tokens) — that is the separate design-token effort; this
  flow **consumes** tokens. New tokens are added only if a required color/gradient is missing.
- Lottie/video cinematics — v1 uses staged text + existing `AppMotion` transitions.
- iOS-specific permission choreography (Android-first).

## Decisions

**1. New `OnboardingPresenter` (ChangeNotifier), constructor-injected.** Holds step index + draft
fields and exposes `previewProfile` (a `TdeeProfile` built from the draft — all derived numbers come
from its getters, satisfying "RPG/TDEE math only in presenters"). Commit methods delegate to
`NutritionPresenter.saveTdeeProfile`/`updateGoals`, `FastingPresenter.updateFastingGoal`,
`QuestPresenter.addQuest`. Interface:

```dart
class OnboardingPresenter extends ChangeNotifier {
  OnboardingPresenter({
    required StorageService storage,
    required NutritionPresenter nutrition,
    required FastingPresenter fasting,
    required QuestPresenter quests,
    required NotificationService notifications,
    required AuthPresenter auth,
  });

  int  get step;                       // 0..8
  void next(); void back();
  Future<void> skip();                 // sets flag, keeps defaults

  void setBody({double? weightKg, double? heightCm, int? ageYears, String? sex});
  void setActivity(ActivityLevel level);
  void setGoal(String goal);           // 'cut' | 'maintain' | 'bulk' | 'recomp'
  TdeeProfile? get previewProfile;     // null until body valid; getters drive Status Window

  int  get protocolHours;              // default 16 (Warrior)
  void setProtocol(int hours);

  bool get cloudProfileFound;          // welcome-back offer after async sync
  Future<void> fastForwardFromCloud();

  Future<void> requestNotifications(); // delegates, never blocks on denial
  Future<void> complete();             // commits profile+goals+protocol, seeds starter quest
                                       // on flag false->true only, sets flag
}
```
_Alternative considered:_ driving the flow from `NutritionPresenter`. Rejected — bloats an already
large presenter and mixes concerns; a dedicated presenter keeps flow state isolated and testable.

**2. Storage flag is device-level / unscoped.** Add `kOnboardingComplete` +
`saveOnboardingComplete`/`loadOnboardingComplete` to `StorageService`; in `LocalStorageService`
bypass the user-scoping key helper (like `kThemeMode`) so it is evaluable before sign-in and
survives `clearUserData`. Not added to any `SyncDomain`.
_Alternative:_ user-scoped flag. Rejected — a fresh device for an existing account must still gate,
and the welcome-back fast-forward keeps that painless.

**3. AppShell gate changes only the branch condition.** In the `initState` post-frame, replace the
"unauthenticated → `LoginView.show()`" branch with "`!onboardingComplete` → show `OnboardingFlow`
(which owns the auth step)". A guest finish still runs `_reloadAll()` + `_setupWidgetBridge()`; a
signed-in finish rides the existing `onFirstSignIn → _initSync` callback. The sync-queue → auth →
login ordering is preserved; the flow slots exactly where `LoginView.show` sat.

**4. Shared step widgets extracted from `TdeeSetupScreen` first, as a behavior-preserving refactor.**
The body/activity/goal form bodies become shared widgets consumed by both `TdeeSetupScreen` (keeps
its own shell) and the wizard. Landed and verified (existing tests green) before any onboarding UI.
_Alternative:_ duplicate the three form bodies. Rejected — guaranteed drift.

**5. Nudgr styling via `Theme.of(context)` + existing system widgets.** Use `AppPageScaffold`,
`AppPrimaryButton`, `AppSegmentedControl`, `AppTextField`, `AppSpacing`/`AppMotion`. Map reference
hex to theme tokens: primary action → blue `#2E90FA` (`colorScheme.primary`/fast accent); System
notice / Status window / First quest → gold `#FFCA28` (`context.appColors.gold`). Add a token only
if a needed value is absent; never hardcode a hex inside a widget.

**6. `OnboardingFlow` is a `PageView` in a `fullscreenDialog` route.** Steps 2–4 render the shared
extracted form widgets; step 1 reuses `LoginView`'s Google/guest actions; step 5 uses
`AppMotion.appear`/`spring` with a count-up ≤400ms.

## Risks / Trade-offs

- **Regressing the auth gate** (AppShell ordering is subtle) → change only the branch condition;
  integration-test both guest and signed-in finishes; keep the exact `_reloadAll()` + widget-bridge
  wiring.
- **Welcome-back race** (cloud pull completes during steps 2+) → presenter re-checks
  `tdeeProfile != null` when sync finishes, not only at sign-in return.
- **Replay foot-gun** (wiping/re-seeding on replay) → guard every one-time effect on the flag
  *transition* (false→true), never on flow completion.
- **`TdeeSetupScreen` extraction churn** → isolated refactor-only commit, verified green before UI.
- **Nudgr token gaps** (a reference color not yet in the theme) → add the missing token in
  `fasting_app.dart`/`app_colors.dart` for both modes; do not inline a hex.

## Migration Plan

Additive and non-breaking. Land in order: (1) storage flag, (2) shared-widget extraction,
(3) presenter, (4) flow UI, (5) AppShell gate, (6) welcome-back, (7) Settings tile,
(8) starter quest + Hub callout. Rollback = revert the branch; the unscoped flag is inert if the
flow code is absent. No DB migration (device-level flag only).

## Open Questions

- Does the current theme already expose a `gold`/`fast` accent via `context.appColors`, or must a
  token be added for the System/Status/Quest gold and blue primary? (Confirm during task 2.)
- Should the one-time Hub "First Quest" callout reuse an existing Hub coach-mark pattern, or is a
  lightweight overlay acceptable? (Prefer reusing an existing pattern if one exists.)
