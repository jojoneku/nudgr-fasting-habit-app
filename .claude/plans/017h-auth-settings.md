# Plan 017h — Auth & Settings Redesign

> Depends on **017** (tokens + theme) and **017W** (widget library) being merged.

## Goal

Polish the entry/exit chrome of the app — login screen and settings — with the design system. Ship the **theme switcher UI** here (the wiring already lives in 017's settings presenter).

---

## Files Touched

| File | Action |
|---|---|
| `lib/views/auth/login_view.dart` | Layout rewrite using `AppPageScaffold`, `AppCard`, `AppTextField`, `AppPrimaryButton` |
| `lib/views/settings_screen.dart` | Sectioned settings list using `AppSection` + `AppListTile`; add theme switcher |

---

## UX Direction

### Login
- Centered column on `AppPageScaffold`
- Top: app logo / wordmark, with `xxl` top spacing
- `AppCard` (filled): title `headlineSmall` "Welcome back" / "Sign in"
  - `AppTextField` for email
  - `AppTextField` for password (with reveal toggle)
  - Forgot-password `TextButton` aligned right
  - `AppPrimaryButton` "Sign in" (full-width, with loading state)
  - Divider with "or"
  - Social buttons row (`AppSecondaryButton` per provider)
- Bottom: "Don't have an account? Sign up" — `TextButton`
- Errors render via `AppToast.error()`

### Settings
- `AppPageScaffold.large(title: 'Settings')` — collapsing large title, HIG canonical
- Body uses `AppGroupedList` — the HIG inset grouped list pattern. One `AppGroupedListSection` per group:
  - **Appearance** — Theme row containing `AppSegmentedControl` (System / Light / Dark); "Use device font size" toggle row
  - **Account** — Profile row, Sign out row
  - **Notifications** — Reminders toggle, Quiet hours row (tap → time picker)
  - **Data** — Export, Sync settings, Clear cache
  - **About** — Version (read-only), Licenses, Feedback link
- Each row: `AppListTile(insetGrouped: true)` with leading `AppIconBadge`, title, optional subtitle, trailing `Switch` / chevron / value text
- Section footer hint where useful (e.g. under **Appearance**: *"Theme follows your device by default."*)
- Destructive rows ("Delete account") render label in error color and confirm via `AppConfirmDialog` (destructive style)

### Theme Switcher Behavior
- Reads / writes via `SettingsPresenter.themeMode` (wired in 017 Phase 2)
- Switch is instant — no app restart
- Persists across launches via `StorageService`

---

## Design-System Widgets Consumed

`AppPageScaffold` (login) · `AppPageScaffold.large` (settings) · `AppCard` · `AppSection` · `AppGroupedList` · `AppListTile` (`insetGrouped: true` in settings) · `AppIconBadge` · `AppTextField` · `AppPrimaryButton` · `AppSecondaryButton` · `AppDestructiveButton` · `AppSegmentedControl` · `AppConfirmDialog` · `AppToast`

---

## Acceptance Criteria

- [ ] Theme switcher present in Settings under "Appearance"
- [ ] Theme change is instant and persists across app restarts
- [ ] Login form works end to end with `AppTextField` + validation
- [ ] Settings uses `AppGroupedList` with inset-style rows (HIG canonical), not flush `AppListTile`s
- [ ] Login uses standard `AppPageScaffold`; Settings uses `AppPageScaffold.large`
- [ ] No hardcoded colors / spacings in either screen
- [ ] Both modes render correctly
- [ ] Destructive actions confirm via `AppConfirmDialog`

---

## Out of Scope

- Auth backend changes (Supabase wiring untouched)
- New auth providers
- New settings categories
