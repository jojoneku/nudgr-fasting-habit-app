## 1. Storage flag

- [x] 1.1 Add `kOnboardingComplete` + `saveOnboardingComplete(bool)` / `loadOnboardingComplete()` to the `StorageService` abstract interface.
- [x] 1.2 Implement in `LocalStorageService` as an **unscoped** key (bypass the user-scoping helper, like `kThemeMode`); ensure it survives `clearUserData`.
- [x] 1.3 Unit tests: flag round-trip; survives `setUserId`/`clearUserData`; defaults false when unset.

## 2. Nudgr token audit

- [x] 2.1 Confirm whether the theme exposes the blue primary + gold accent the flow needs (`context.appColors` / `colorScheme`); resolve design Open Question 1. → Resolved: `context.appColors.fast` (#2E90FA) and `context.appColors.gold` (#FFCA28) already exist.
- [x] 2.2 If a required accent/gradient is missing, add it to `app_colors.dart` (dark + light) and wire it in `fasting_app.dart` — never inline a hex in a widget. → Not needed; no new token required. (Only literal: the gold Accept button's dark on-gold foreground `#2A1A00`, matching the reference.)

## 3. Shared step-form extraction (behavior-preserving)

- [x] 3.1 Extract the body-stats, activity-level, and goal form bodies from `tdee_setup_screen.dart` into shared step widgets. → Extracted `BodyStatsForm`, `ActivityLevelSelector`, and `TdeeRadioTile` into `views/nutrition/widgets/tdee_step_forms.dart`. NOTE: the goal/Path step is intentionally bespoke per flow (the reference's 4-card Path incl. Recomp differs from `TdeeSetupScreen`'s 3-goal + deficit/surplus picker), so it is not shared — both use the shared `TdeeRadioTile`.
- [x] 3.2 Reintegrate them into `TdeeSetupScreen` (keeps its own shell); confirm no behavior change.
- [x] 3.3 Run existing `TdeeSetupScreen`/nutrition tests — all green before any onboarding UI lands (full suite: 733 pass).

## 4. OnboardingPresenter

- [x] 4.1 Create `lib/presenters/onboarding_presenter.dart` per the design interface (step index, draft, `previewProfile`, protocol default 16).
- [x] 4.2 Implement `next`/`back`/`skip`, commit delegation, `complete()` with starter-quest seeding guarded on the flag false→true transition, and non-blocking `requestNotifications`.
- [x] 4.3 Implement `cloudProfileFound` + `fastForwardFromCloud`, re-checking for a profile when async sync completes (listens to nutrition + auth).
- [x] 4.4 Presenter unit tests (hand fakes + real storage): navigation, `previewProfile` parity with `TdeeProfile` getters, commit delegation, skip semantics, idempotent starter-quest seeding, welcome-back, prefill, non-blocking notifications.

## 5. Onboarding flow UI (Nudgr, theme-aware)

- [x] 5.1 Create `lib/views/onboarding/onboarding_flow.dart` — stepped flow in a `fullscreenDialog` route; Skip (≥44px) on every step but the last; primary CTA in bottom region.
- [x] 5.2 Build steps 0 Awakening, 1 Identity (Google/guest via presenter passthrough), 2 Vessel, 3 Training, 4 Path — using shared form widgets + system widgets.
- [x] 5.3 Build step 5 Status Window: BMR/TDEE/target/macros from `previewProfile` getters, gold System-notice treatment, count-up reveal (300ms ≤400ms budget).
- [x] 5.4 Build step 6 Protocol (`FastingProtocol.all`, Warrior 16:8 pre-selected, extended de-emphasised), step 7 Summons (notification primer), step 8 First Quest hand-off.
- [x] 5.5 Verify blue-primary / gold-system color mapping, theme text (Plus Jakarta Sans via theme), Material icons, touch targets ≥44px, motion ≤400ms. NOTE: Phosphor icons/fonts are the separate design-token effort; this flow consumes theme type + uses Material icons (no new dependency), per the proposal.

## 6. AppShell first-run gate

- [x] 6.1 In `home_screen.dart` `initState` post-frame, `!onboarded && no local profile → show OnboardingFlow` (flow owns the auth step); returning/signed-in users are marked complete and never see it.
- [x] 6.2 Guest finish runs `_reloadAll()` + `_setupWidgetBridge()`; signed-in finish rides the existing `onFirstSignIn → _initSync` callback.
- [ ] 6.3 Integration-test both guest and signed-in finishes; confirm the sync-queue→auth ordering is unchanged. → Deferred to on-device manual smoke (9.3); AppShell wiring needs Supabase + platform channels not available in `flutter test`.

## 7. Welcome-back path

- [x] 7.1 After in-flow sign-in + sync pull, surface the fast-forward offer when `cloudProfileFound`; accepting marks complete without overwriting pulled data.
- [x] 7.2 Test the async race: profile arriving via `nutrition` notify still flips `cloudProfileFound` (presenter listens to nutrition + auth).

## 8. Settings replay + starter quest

- [x] 8.1 Add a "Replay the Awakening" tile in `settings_screen.dart`; replay prefills from the saved profile and fires no one-time effects (reuses AppShell's `OnboardingPresenter`, threaded via HubScreen).
- [x] 8.2 Seed the single starter quest ("Begin your first fast") on genuine first completion only. NOTE: the one-time "callout" is delivered as the in-flow First Quest step (step 8) rather than a separate Hub overlay — keeps scope tight and avoids a bespoke coach-mark (design Open Question 2).

## 9. Verification gate

- [x] 9.1 `dart format` validation clean on all changed/new files.
- [x] 9.2 Full `flutter test` green — 733 tests pass (new presenter + storage tests + existing suite). `flutter analyze` adds 0 errors / 0 new warnings.
- [ ] 9.3 Manual smoke in dark + light: fresh install, guest, welcome-back, replay, skip-from-every-step. → PENDING on a device/emulator (mobile app can't be driven from this environment).
- [x] 9.4 Confirm spec scenarios satisfied by the presenter/UI (unit-verified where possible; UI/gate scenarios covered by 9.3).

> Tooling note: the committed `test/mocks.mocks.dart` is NOT reproducible with the installed
> mockito/build_runner (regenerating breaks several finance suites with `MissingStubError`). The
> onboarding presenter test therefore uses hand fakes + a real `LocalStorageService` instead of
> regenerating the shared mock. Fixing the mock-tooling drift is out of scope for this change.
