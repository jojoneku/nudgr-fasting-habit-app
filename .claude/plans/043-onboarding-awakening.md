# Plan 043 — Onboarding Wizard ("The Awakening")

> Status: PLANNED — NOT IMPLEMENTED · June 10, 2026
> Spec: [docs/onboarding_spec.md](../../docs/onboarding_spec.md)
> Branch: **`feat/043-onboarding-awakening`** off `dev`. Own PR, `--base dev`.

## Goal
Give new Players a themed first-run sequence — awaken as a hunter, sign in (or walk alone),
build the body profile, see computed TDEE/macros as **starting stats**, pick a fasting protocol,
prime notifications, land on the Hub with a starter quest. Today none of this exists: `AppShell`
shows `LoginView` and dumps the user on the Hub with a null `TdeeProfile`, a generic 2,000 kcal
goal, and a silent 16h fasting default. The setup that matters is buried in
`nutrition_settings_sheet.dart:395` → `TdeeSetupScreen`.

## Key findings (verified)
- **All TDEE math already exists** as getters on `TdeeProfile` (Mifflin-St Jeor `bmr`, `tdee`,
  `targetCalories`, `suggestedProteinG/FatG/CarbsG`). The wizard adds **zero math** — it builds a
  draft `TdeeProfile` and reads the getters. RPG-math-in-presenters rule is satisfied by keeping
  step/flow state in a new presenter.
- `TdeeSetupScreen` (778 lines) is already a 4-step wizard with body/activity/goal/review steps —
  steps 2–4 of onboarding extract and reuse its form bodies rather than re-implementing them.
- Goal values are `'cut' | 'maintain' | 'bulk' | 'recomp'` (`bulk` displays as **"Lean gain"**).
- Protocol presets live in `FastingProtocol.all` (`protocol_card.dart`) with RPG names
  (12:12 Initiate → 48h Void Protocol); commit via `FastingPresenter.updateFastingGoal(hours)`.
- Guest mode exists: `LoginView`'s "Log in later" pops, then `AppShell` runs `_reloadAll()` +
  `_setupWidgetBridge()`. The flow must preserve that exact wiring.
- `NotificationService.requestPermissions()` exists (line ~214).
- `QuestPresenter.addQuest(Quest)` exists for the starter quest.

## Conflict Check

| Check | Finding |
|---|---|
| **File overlap** | Touches `home_screen.dart` (AppShell gate) — Plan 039 (merged) also edited it; rebase off current `dev`. Adds a Settings tile — **Plan 044 also adds one** (`settings_screen.dart`); trivial merge, but sequence the PRs. Extracts step widgets from `tdee_setup_screen.dart` (refactor-only, no behavior change). |
| **Model overlap** | None. No new models; reuses `TdeeProfile`, `NutritionGoals`, `Quest`. |
| **StorageService keys** | New `kOnboardingComplete` (device-level, unscoped — like `kThemeMode`). No clash with existing keys. |
| **XP routing** | No XP awarded by the flow itself. Starter quest pays through the existing quest loop. |
| **HubScreen** | One-time "First Quest" callout — use existing Hub patterns, no new constructor params beyond the presenter. |
| **Supersedes** | None. `LoginView` is retained (re-auth path) and embedded as step 1. |
| **Dependency order** | Standalone. Prefer merging before 044 to settle `settings_screen.dart`. |

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/presenters/onboarding_presenter.dart` | Create | Presenter |
| `lib/views/onboarding/onboarding_flow.dart` | Create | View |
| `lib/views/onboarding/steps/*.dart` (awakening, identity, vessel, training, path, status_window, protocol, summons) | Create | View |
| `lib/views/nutrition/tdee_setup_screen.dart` | Modify (extract shared step form widgets) | View |
| `lib/views/widgets/onboarding/` or `lib/views/nutrition/widgets/` shared step bodies | Create | View |
| `lib/services/storage_service.dart` + `local_storage_service.dart` | Modify (flag) | Service |
| `lib/views/home_screen.dart` | Modify (first-run gate in `initState` post-frame) | View |
| `lib/views/settings_screen.dart` | Modify ("Replay the Awakening" tile) | View |

## Interface Definitions

```dart
// === StorageService additions ===
static const String kOnboardingComplete = 'onboardingComplete'; // device-level, unscoped
Future<void> saveOnboardingComplete(bool value);
Future<bool> loadOnboardingComplete();

// === OnboardingPresenter (new) ===
class OnboardingPresenter extends ChangeNotifier {
  OnboardingPresenter({
    required StorageService storage,
    required NutritionPresenter nutrition,
    required FastingPresenter fasting,
    required QuestPresenter quests,
    required NotificationService notifications,
    required AuthPresenter auth,
  });

  int get step;                       // 0..8
  void next(); void back(); 
  Future<void> skip();                // sets flag, keeps defaults

  // Draft (steps 2–4) — mirrors TdeeSetupScreen state
  void setBody({double? weightKg, double? heightCm, int? ageYears, String? sex});
  void setActivity(ActivityLevel level);
  void setGoal(String goal);          // 'cut' | 'maintain' | 'bulk' | 'recomp'
  TdeeProfile? get previewProfile;    // null until body fields valid; getters drive step 5

  int  get protocolHours;             // default 16 (Warrior Mode)
  void setProtocol(int hours);

  bool get cloudProfileFound;         // welcome-back fast-forward offer after sign-in
  Future<void> fastForwardFromCloud();

  Future<void> requestNotifications(); // delegates, never blocks on denial
  Future<void> complete();            // commits profile+goals+protocol, seeds starter
                                      // quest (first completion only), sets flag
}
```

## Implementation Order
1. [ ] **Storage flag** — key + save/load in interface and `LocalStorageService` (unscoped: bypass
       `_k()`, survive `clearUserData`). Unit tests.
2. [ ] **Extract shared step widgets** from `TdeeSetupScreen` (body stats / activity / goal form
       bodies) with no behavior change; `TdeeSetupScreen` keeps its own shell. Run existing tests.
3. [ ] **OnboardingPresenter** — draft state, `previewProfile`, commit delegation, skip,
       fast-forward, starter-quest idempotency. Pure presenter tests with mocks (no View).
4. [ ] **OnboardingFlow view** — PageView shell + 9 steps; embed `AuthPresenter` actions for step 1
       (reuse `LoginView` visual pieces); status-window reveal with `AppMotion.appear`/`spring`,
       count-up ≤400ms; Skip on every step; system widgets + theme-aware colors only.
5. [ ] **AppShell gate** — post-frame: `!onboardingComplete` → show flow (flow owns auth);
       else current logic untouched. Guest finish runs `_reloadAll()` + `_setupWidgetBridge()`;
       signed-in finish rides the existing `onFirstSignIn → _initSync` callback.
6. [ ] **Welcome-back path** — after in-flow sign-in + sync pull, `cloudProfileFound` offers
       fast-forward; accepting marks complete without overwriting pulled data.
7. [ ] **Settings tile** — "Replay the Awakening" (prefilled; no quest re-seed).
8. [ ] **Hub callout + starter quest** — seed `Quest('First Quest: Begin your fast', …)` on first
       genuine completion only.
9. [ ] **Format/test gate** — `dart format` validation, `flutter analyze`, full `flutter test`,
       manual smoke in both themes (fresh install / guest / welcome-back / replay / skip).

## RPG Impact
- XP awarded: **none** from the flow itself; the starter quest is the first XP hook.
- Level/streak: untouched.
- Notifications: permission primed in step 7; nothing scheduled by the flow itself
  (fasting/quest notifications schedule as today once the user acts).

## Risks
- **Regressing the auth gate** — `AppShell.initState` ordering (sync queue → auth → login) is
  subtle; the flow must slot in where `LoginView.show` sits today and keep the guest wiring.
  Mitigation: step 5 changes only the branch condition; integration-test both paths.
- **`TdeeSetupScreen` extraction churn** — refactor-only commit, isolated and verified before any
  onboarding UI lands; fallback is duplicating the three form bodies (accepted drift risk, avoid).
- **Welcome-back race** — cloud pull completes asynchronously during steps 2+; presenter must
  re-check `tdeeProfile != null` when sync finishes, not only at sign-in return.
- **Replay foot-gun** — replay must never wipe or re-seed; guard all one-time effects on the
  flag *transition*, not on flow completion.

## UX Verification
- [ ] Primary CTA in bottom 30% of screen on every step
- [ ] All touch targets ≥ 44×44px (incl. Skip)
- [ ] Micro-animations 150–300ms; stat count-up ≤ 400ms; no animation > 400ms
- [ ] Status window glanceable in < 1 second
- [ ] Dark and light themes both verified (theme-aware colors only)

## Acceptance Criteria
- [ ] Spec §6 criteria 1–8 all pass.
- [ ] `TdeeSetupScreen` behavior unchanged after extraction (existing tests green).
- [ ] New presenter + storage tests green; `dart format` + `flutter analyze` clean.
