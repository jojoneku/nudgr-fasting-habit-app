## ADDED Requirements

### Requirement: First-run gate
The app SHALL show the Onboarding "Awakening" flow before the Hub on first run, gated by a
device-level (unscoped) persisted `onboardingComplete` flag stored through `StorageService`. The
flag MUST be evaluable before sign-in, MUST survive sign-out / account switch (it is not part of any
`SyncDomain`), and once set MUST NOT re-trigger the flow for returning users.

#### Scenario: Fresh install shows the flow
- **WHEN** the app launches and `onboardingComplete` is false
- **THEN** the Awakening flow is presented before the Hub

#### Scenario: Returning user is never gated
- **WHEN** the app launches and `onboardingComplete` is true
- **THEN** the flow does not appear and the app behaves exactly as it does today

#### Scenario: Flag persists across sign-out
- **WHEN** `onboardingComplete` is true and the user signs out (which clears user-scoped data)
- **THEN** the flag remains true and the flow does not reappear on next launch

### Requirement: Step flow and navigation
The flow SHALL present ordered steps — Awakening, Identity, Vessel, Training, Path, Status Window,
Protocol, Summons, **Review**, First Quest. Each input step (Identity through Summons) MUST expose a
per-step **Skip** control (≥44×44px) that advances to the next step (skipping only that step, not the
whole flow). **Back** MUST be available on every step after the first and MUST NOT lose values
already entered, because draft state lives in the presenter rather than in widget state.

#### Scenario: Forward and back preserve draft
- **WHEN** the user enters body values on Vessel, advances, then returns via Back
- **THEN** the previously entered values are still present

#### Scenario: Per-step skip advances without exiting
- **WHEN** the user taps Skip on an input step
- **THEN** the flow moves to the next step and does not exit or mark onboarding complete

#### Scenario: A skipped input step does not dead-end the Status Window
- **WHEN** the body step was skipped and the Status Window is reached
- **THEN** the Status Window still offers a way to add details or continue

### Requirement: Review before finish
Before the finishing step, the flow SHALL present a **Review** step summarising every input —
account/identity, body basics, activity level, goal, computed daily target, and fasting protocol.
Each summarised item MUST offer an **Edit** action that jumps to its step; after editing, the next
advance MUST return directly to the Review step rather than continuing forward. Confirming Review
proceeds to the finish.

#### Scenario: Review lists all inputs
- **WHEN** the Review step is shown
- **THEN** it displays the account, body, activity, goal, daily target, and protocol values (or
  "Not set" for anything skipped)

#### Scenario: Edit returns to Review
- **WHEN** the user taps Edit on an item, changes it, and advances
- **THEN** the flow returns to the Review step with the updated value shown

### Requirement: Identity step and guest mode
The Identity step SHALL offer **Continue with Google** and **Walk alone for now** (guest). Choosing
guest MUST complete the flow with no session and wire presenters and widgets identically to today's
"Log in later" path (`_reloadAll()` + widget bridge setup). Signing in later MUST still trigger the
existing cloud sync.

#### Scenario: Walk alone stays on device
- **WHEN** the user chooses "Walk alone for now"
- **THEN** no session is created and the app is wired the same as today's guest path

#### Scenario: Sign in during onboarding
- **WHEN** the user chooses Continue with Google and authentication succeeds
- **THEN** the existing sign-in sync runs as it does today

### Requirement: Welcome-back fast-forward
When sign-in during the flow pulls existing cloud data containing a `TdeeProfile`, the flow SHALL
offer a fast-forward that marks onboarding complete and lands on the Hub without overwriting the
pulled profile. Because the cloud pull is asynchronous, the presenter MUST re-check for a profile
when sync completes, not only at the moment sign-in returns.

#### Scenario: Existing record found
- **WHEN** sign-in completes and the synced data already contains a `TdeeProfile`
- **THEN** the flow offers to fast-forward and, on accept, completes without re-asking profile steps

#### Scenario: Pulled profile is not overwritten
- **WHEN** the user accepts the fast-forward
- **THEN** the cloud-pulled `TdeeProfile` and goals remain unchanged

### Requirement: Profile capture reuses existing math
Steps Vessel, Training, and Path SHALL capture body basics (age, sex, height, weight), activity
level, and goal (`cut` / `maintain` / `bulk` (displayed "Lean gain") / `recomp`). The Status Window
step SHALL display BMR, TDEE, daily target, and suggested macros computed **only** from the existing
`TdeeProfile` getters — the flow MUST NOT introduce any new nutrition math. On confirm, the flow
SHALL persist the resulting `TdeeProfile` and macro-filled `NutritionGoals`.

#### Scenario: Numbers match the existing editor
- **WHEN** the same body/activity/goal inputs are entered in the flow and in `TdeeSetupScreen`
- **THEN** the Status Window's BMR, TDEE, target, and macros equal `TdeeProfile.bmr` / `tdee` /
  `targetCalories` / `suggestedProteinG` / `suggestedFatG` / `suggestedCarbsG` for those inputs

#### Scenario: Confirm persists a real profile
- **WHEN** the user confirms the Status Window
- **THEN** a non-null `TdeeProfile` and macro-filled `NutritionGoals` are saved and survive restart

### Requirement: Fasting protocol selection
The Protocol step SHALL present fasting presets from `FastingProtocol.all` with their RPG names,
pre-selecting the 16:8 "Warrior" protocol, and commit the choice via
`FastingPresenter.updateFastingGoal(hours)`. Extended protocols MAY be visually de-emphasized for
new players but MUST remain selectable.

#### Scenario: Default and commit
- **WHEN** the Protocol step is shown and the user continues without changing the selection
- **THEN** a 16h fasting goal is committed via `updateFastingGoal`

### Requirement: Notification primer is non-blocking
The Summons step SHALL explain notification value and request OS permission via
`NotificationService.requestPermissions()`. Denying or skipping MUST NOT block flow completion.

#### Scenario: Denial does not block
- **WHEN** the user denies or skips the notification request
- **THEN** the flow continues and completes normally

### Requirement: Starter quest seeding is idempotent
On the first genuine completion of the flow (the `onboardingComplete` transition from false to
true), the app SHALL seed exactly one starter quest ("Begin your first fast"). The flow itself
SHALL award no XP. Re-running the flow MUST NOT seed the quest again or re-award anything.

#### Scenario: Seeded once on first completion
- **WHEN** the flow is completed for the first time
- **THEN** exactly one starter quest is added and no XP is granted by the flow

#### Scenario: Replay does not re-seed
- **WHEN** the flow is re-run after already being completed
- **THEN** no additional starter quest is created

### Requirement: Bail preserves current defaults
Bailing out of the whole flow (the "Skip for now" action on the first screen) SHALL mark
`onboardingComplete` true, keep today's defaults (2,000 kcal simple goal, 16h fasting), land on the
Hub, and prevent the flow from reappearing. (This is distinct from per-step Skip, which only
advances one step.)

#### Scenario: Bail from the first screen
- **WHEN** the user taps "Skip for now" on the first screen
- **THEN** the app lands on the Hub with today's defaults and the flow never reappears

### Requirement: Replay from Settings
Settings SHALL offer a "Replay the Awakening" entry that re-runs the flow prefilled from the saved
profile. Replay MUST NOT wipe data, re-seed the starter quest, or re-award anything.

#### Scenario: Prefilled replay
- **WHEN** the user opens "Replay the Awakening" with a saved profile
- **THEN** the steps are prefilled from that profile and no one-time effects fire again

### Requirement: Nudgr visual language and dual theme
The flow SHALL render in the Nudgr design language using theme-aware colors only (no hardcoded
`AppColors`/`AppColorsLight` inside widgets): blue `#2E90FA` for primary actions, gold `#FFCA28`
reserved for System-notice / Status-window / First-quest moments, Plus Jakarta Sans type, Phosphor
iconography. It MUST render correctly in both dark and light themes, keep every touch target
≥44×44px, place the primary CTA in the bottom 30% of the screen, and keep all animations ≤400ms
(micro-interactions 150–300ms; Status Window count-up ≤400ms).

#### Scenario: Both themes render
- **WHEN** the flow is displayed in dark mode and in light mode
- **THEN** every step renders correctly with theme-aware colors in both

#### Scenario: Motion budget respected
- **WHEN** any step transition or the Status Window reveal plays
- **THEN** no animation exceeds 400ms

### Requirement: No removal of existing entry points
Introducing the flow SHALL NOT remove `LoginView` (retained as the re-auth path and reused for the
Identity step visuals) or `TdeeSetupScreen` (retained as the in-app edit path). Shared step-form
widgets extracted from `TdeeSetupScreen` MUST preserve its existing behavior.

#### Scenario: Editor unchanged after extraction
- **WHEN** body/activity/goal form bodies are extracted into shared widgets
- **THEN** `TdeeSetupScreen` behaves exactly as before and its existing tests pass
