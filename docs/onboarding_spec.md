# Onboarding Spec — "The Awakening"

> Status: PLANNED — NOT IMPLEMENTED · June 10, 2026 · Owner: Core loop
> Plan: [.claude/plans/043-onboarding-awakening.md](../.claude/plans/043-onboarding-awakening.md)
> Related: `TdeeProfile`, `NutritionPresenter`, `FastingPresenter`, `AuthPresenter`, `LoginView`

## 1. Problem

There is **no guided first-run flow**. Verified current behavior:

- `main.dart` → `FastingApp` → `AppShell` (`home_screen.dart`). The only first-run gate is the
  post-frame check in `AppShell.initState`: unauthenticated users get `LoginView.show()` (Google
  sign-in or "Log in later" guest mode) and are then dropped straight onto the Hub.
- `TdeeProfile` starts **null** (`loadTdeeProfile()` returns null until saved); `NutritionGoals`
  defaults to `NutritionGoals.initial()` = a generic 2,000 kcal simple mode.
- The only path to a real profile is buried three taps deep: Nutrition → settings sheet
  (`nutrition_settings_sheet.dart:395`) → `TdeeSetupScreen`.
- `FastingPresenter.fastingGoalHours` silently defaults to 16; the protocol picker
  (`FastingProtocol.all` in `protocol_card.dart`) is never surfaced to a new user.
- Notification permission is requested ad-hoc, with no primer explaining why.

A new Player meets an empty Hub with placeholder stats instead of an *awakening*.

## 2. Goals

1. A themed first-run wizard — **The Awakening** — that fits the Solo Leveling identity:
   the user is "chosen as a Player," builds their profile, and sees their **starting stats**.
2. Produce a real `TdeeProfile` + `NutritionGoals` + fasting protocol on day one, reusing the
   **existing math** (Mifflin-St Jeor BMR/TDEE/macros are getters on `TdeeProfile` — zero new math).
3. Fold the existing sign-in step (Google / "Log in later") into the flow without breaking guest mode.
4. Skippable at any step; re-runnable from Settings; never blocks a returning user.
5. Persist an `onboardingComplete` flag through `StorageService`.

### Non-goals
- Replacing `TdeeSetupScreen` (it remains the in-app edit path; shared step widgets are extracted).
- Animated video/lottie cinematics — v1 uses staged text + `AppMotion` transitions only.
- iOS-specific permission flows (app is Android-first).

## 3. Flow

| # | Step | Content | Writes |
|---|---|---|---|
| 0 | **Awakening** | Dark, staged reveal: *"You have been chosen as a Player."* CTA: **[ Accept ]** | — |
| 1 | **Identity** | Sign in with Google or *"Walk alone for now"* (guest = existing "Log in later") | session via `AuthPresenter` |
| 2 | **Vessel** | Body basics: age, sex, height, weight | draft only |
| 3 | **Training** | Activity level (`ActivityLevel.sedentary…veryActive`) | draft only |
| 4 | **Path** | Goal: Cut / Maintain / Lean gain (`bulk`) / Recomp — values verified against `TdeeProfile.goal` | draft only |
| 5 | **Status Window** | Computed BMR, TDEE, target kcal, suggested macros presented as **starting stats** (stat-window card, count-up reveal ≤ 400ms) | `saveTdeeProfile` + `updateGoals` on confirm |
| 6 | **Protocol** | Fasting protocol picker from `FastingProtocol.all` (Warrior Mode 16:8 pre-selected) | `updateFastingGoal(hours)` |
| 7 | **Summons** | Notification primer → `NotificationService.requestPermissions()` (skippable) | OS permission |
| 8 | **First Quest** | Land on Hub; seed one starter quest + one-time Hub callout | `addQuest`, `onboardingComplete = true` |

Rules:
- **Skip** is visible on every step (top-right, ≥44px). Skipping marks `onboardingComplete = true`
  and keeps defaults (2,000 kcal / 16h) — identical to today's behavior.
- **Back** never loses entered values (draft lives in the presenter, not widget state).
- **Welcome back, Hunter:** step 1 sign-in triggers the existing `_initSync` cloud pull. If the
  pulled data already contains a `TdeeProfile`, offer a fast-forward ("Your record was found")
  that marks complete and lands on the Hub — a reinstalling user is never forced to re-answer.
- Re-running from Settings prefills from the saved profile and **never** re-seeds the starter
  quest or re-awards anything.

## 4. Architecture

| Layer | Piece |
|---|---|
| Presenter | New `OnboardingPresenter` (`ChangeNotifier`): step index, draft fields, `previewProfile` (a `TdeeProfile` built from the draft — all derived numbers come from its getters), commit methods that delegate to `NutritionPresenter.saveTdeeProfile`/`updateGoals`, `FastingPresenter.updateFastingGoal`, `QuestPresenter.addQuest`. Constructor injection only. |
| View | New `lib/views/onboarding/onboarding_flow.dart` (PageView shell, `fullscreenDialog`) + step widgets. Steps 2–4 reuse form widgets **extracted** from `TdeeSetupScreen` into shared step components so the two flows cannot drift. System widgets (`AppPageScaffold`, `AppPrimaryButton`, `AppSegmentedControl`, `AppTextField`), `AppSpacing`/`AppMotion` tokens, theme-aware colors only. |
| Service | `StorageService`: `kOnboardingComplete` + `saveOnboardingComplete`/`loadOnboardingComplete`. |
| Entry | `AppShell.initState` post-frame: `if (!onboardingComplete)` → show `OnboardingFlow` (which owns the auth step) instead of `LoginView`; otherwise current behavior is untouched. Guest finish must still run `_reloadAll()` + `_setupWidgetBridge()` exactly as the current guest path does. |

### Persistence & sync
`kOnboardingComplete` is a **device-level (unscoped)** key, like `kThemeMode` — the gate must be
evaluable *before* sign-in, and a fresh device should awaken even for an existing account (the
welcome-back fast-forward keeps that painless). It is **not** added to any `SyncDomain`.

## 5. RPG framing & copy

- Stat reveal uses the "status window" visual language (gold accents via `context.appColors.gold`,
  same treatment as `TdeeSetupScreen`'s review step).
- Protocol step shows the existing RPG names (Initiate Protocol → Void Protocol); extended
  protocols (36h/48h) are visible but de-emphasized for new players.
- Completing the full flow awards **no XP** (profile setup is not a feat); the starter quest is
  the first XP opportunity.
- Starter quest: a single enabled daily `Quest` ("First Quest: Begin your fast") seeded only on
  the first genuine completion (flag transition false → true through step 8).

## 6. Acceptance criteria

1. Fresh install: Awakening flow appears before the Hub; completing it persists `TdeeProfile`,
   macro-filled `NutritionGoals`, and the chosen `fastingGoalHours` (all survive restart).
2. Numbers shown in step 5 exactly match `TdeeProfile.bmr/tdee/targetCalories/suggested*` for the
   same inputs entered through `TdeeSetupScreen` (shared math, no duplication).
3. "Walk alone" (guest) completes the flow with no session; widgets and presenters are wired the
   same as today's "Log in later" path; signing in later still triggers sync as before.
4. Sign-in during onboarding with existing cloud data offers fast-forward and does not overwrite
   the pulled profile.
5. Skip at any step lands on the Hub with today's defaults; flag set; flow never reappears.
6. Settings → "Replay the Awakening" re-runs prefilled; no duplicate starter quest.
7. Notification step denial is non-blocking; flow completes normally.
8. Both themes render correctly; all targets ≥44px; transitions ≤400ms; `flutter analyze`/`dart format` clean.

## 7. Test plan

- `onboarding_presenter_test`: step navigation, draft → `previewProfile` parity with `TdeeProfile`
  getters, commit delegation (mock presenters), skip semantics, idempotent starter-quest seeding.
- `local_storage_service_test`: flag round-trip, unscoped (survives `setUserId`/`clearUserData`).
- Widget: flow renders each step in dark + light; skip from every step; back preserves input.
- Manual: fresh install, guest path, welcome-back path, replay from Settings.
