## Why

The app has **no guided first-run flow**. A new Player is dropped straight onto the Hub with a
null `TdeeProfile`, a generic 2,000 kcal goal, and a silent 16h fasting default; the only path to a
real profile is buried three taps deep in Nutrition settings. A themed first-run wizard —
**The Awakening** — was fully specced (`docs/onboarding_spec.md`, `.claude/plans/043`) but never
built. The Nudgr redesign reference now gives us the finished visual language for it, so this is
the moment to **finally implement it and restyle it into Nudgr** in one pass — the first screen of
the broader UI redesign, and the first spec authored under OpenSpec.

This is a **restyle + finally-implement**, not a net-new flow: the 9-step sequence, the reuse of
existing Mifflin-St Jeor math, and the guest/welcome-back semantics all come straight from the
existing spec. What is new is the Nudgr skin and turning the spec into shipping code.

## What Changes

- Add a first-run **Onboarding "Awakening"** wizard: 9 steps — Awakening → Identity → Vessel →
  Training → Path → Status Window → Protocol → Summons → First Quest.
- Produce a real `TdeeProfile` + macro-filled `NutritionGoals` + chosen fasting protocol on day one,
  reusing the **existing** `TdeeProfile` getters (BMR/TDEE/target/macros) — **zero new math**.
- Fold the existing Google / "Walk alone" (guest) sign-in in as step 1 without breaking guest mode;
  offer a **welcome-back fast-forward** when sign-in pulls a cloud profile.
- Gate first run in `AppShell` on a new **device-level `onboardingComplete`** flag; skippable on
  every step (keeps today's defaults); re-runnable from Settings ("Replay the Awakening").
- Restyle the whole flow into the **Nudgr design language**: Plus Jakarta Sans, Phosphor icons,
  blue `#2E90FA` primary actions, gold `#FFCA28` reserved for the System-notice / status-window /
  first-quest moments, domain-semantic accents — all via theme-aware tokens (no hardcoded colors).
- Extract the body/activity/goal form bodies from `TdeeSetupScreen` into shared step widgets so the
  wizard and the in-app editor cannot drift.
- Seed one starter quest ("Begin your first fast") on genuine first completion only.

Non-breaking. No existing feature or component is removed — `LoginView` and `TdeeSetupScreen` are
retained (re-auth path and in-app edit path); the reference's absence of a screen never justifies
deleting it.

## Capabilities

### New Capabilities
- `onboarding`: First-run "Awakening" wizard — step flow and navigation, guest/sign-in identity
  step with welcome-back fast-forward, TDEE profile + goals + fasting-protocol capture (reusing
  existing math), notification primer, starter-quest seeding, the `onboardingComplete` gate,
  skip/replay semantics, and Nudgr-language visual requirements.

### Modified Capabilities
<!-- None. openspec/specs/ is currently empty; TdeeSetupScreen changes are a behavior-preserving
     widget extraction (implementation detail), not a spec-level requirement change. -->

## Impact

- **New:** `lib/presenters/onboarding_presenter.dart`; `lib/views/onboarding/` (flow shell + 8 step
  widgets); shared step-form widgets extracted from `TdeeSetupScreen`.
- **Modified:** `StorageService` + `LocalStorageService` (add unscoped `kOnboardingComplete`);
  `lib/views/home_screen.dart` (AppShell first-run gate replaces the `LoginView`-only branch);
  `lib/views/settings_screen.dart` (add "Replay the Awakening" tile);
  `lib/views/nutrition/tdee_setup_screen.dart` (extract shared step bodies, no behavior change);
  `lib/views/fasting_app.dart` only if new Nudgr theme tokens are required.
- **Reuses (unchanged):** `TdeeProfile`, `NutritionGoals`, `FastingProtocol.all`,
  `NutritionPresenter`, `FastingPresenter`, `QuestPresenter`, `AuthPresenter`, `NotificationService`.
- **Deps:** none new expected (Plus Jakarta Sans / Phosphor adoption tracked under the separate
  Nudgr design-token effort; this flow consumes tokens, it does not define the global theme).
- **Sequencing:** `onboardingComplete` is device-level/unscoped (like `kThemeMode`) and is **not**
  added to any `SyncDomain`. Coordinate the `settings_screen.dart` tile with any concurrent
  Settings work.
