# Plan 039 — Android Home-Screen Widgets (Core Logging Glances + Quick Actions)

> Platform: **Android now, iOS later** (the Dart bridge is architected so a WidgetKit extension
> can be added in a follow-up without reworking the data layer).
> Interaction: **inline quick-actions where safe** (Start/End fast, complete quest) + **deep-link**
> for richer flows (food / expense entry).
> Spec: `docs/android_widgets_spec.md`

## Goal
Put The System on the home screen. Glanceable widgets for the four core loops — **fasting timer,
food logging, expense logging, weight + quests** — so the user feels the RPG pull without opening
the app, and can fire the highest-value actions (start/end a fast, complete a quest) in one tap.

## The central constraint
`LocalStorageService` prefixes **all** user data with `u/$userId/`, set only after auth. The native
widget runs in a separate process (and, for inline actions, a headless Flutter isolate) with **no
auth session and no userId**. So:
1. Widgets never read app prefs directly — the app **pushes** a denormalized `WidgetSnapshot` into
   `home_widget`'s own unscoped prefs.
2. Sign-out clears the snapshot (shared-device privacy).
3. The fasting timer ticks without the Flutter process via a native `Chronometer`.

## Affected Files
| File | Action | Layer |
|---|---|---|
| `pubspec.yaml` | Modify — add `home_widget` | Deps |
| `lib/models/widget/widget_snapshot.dart` | Create | Model |
| `lib/services/widget_bridge_service.dart` | Create | Service |
| `lib/services/storage_service.dart` (+ `local_storage_service.dart`) | Modify — device-level keys | Service |
| `lib/main.dart` | Modify — register background callback; handle launch deep-link | Entry |
| `lib/views/home_screen.dart` (AppShell) | Modify — construct bridge, wire to presenters, route deep-links, clear on sign-out | View |
| `android/app/src/main/kotlin/com/nudgr/app/MainActivity.kt` | Modify — parse deep-link intents | Native |
| `android/app/src/main/AndroidManifest.xml` | Modify — providers, receivers, deep-link intent-filter | Native |
| `android/app/src/main/res/xml/widget_*_info.xml` | Create — appwidget-provider configs | Native |
| `android/app/src/main/res/layout/widget_*.xml` | Create — RemoteViews layouts | Native |
| `android/app/src/main/res/values{,-night}/widget_colors.xml` | Create — token mirror | Native |
| `android/app/src/main/res/drawable/widget_*.xml` | Create — backgrounds, ring | Native |
| `android/app/src/main/kotlin/.../*WidgetProvider.kt` | Create — one provider per widget | Native |
| `test/services/widget_bridge_service_test.dart` | Create | Test |

> Native widget visuals can't read `Theme.of(context)` — use `values/` vs `values-night/` mirroring
> `AppColors` / `AppColorsLight`. Document in file headers.

## Implementation Order
- **Phase 0 — Foundation:** home_widget dep, `WidgetSnapshot`, device-level keys + last userId,
  `WidgetBridgeService`, wire into AppShell + clear-on-signout, register background callback.
- **Phase 1 — Fasting flagship:** `FastingWidgetProvider` + Chronometer layout, deep-link
  intent-filter + `MainActivity` parsing, inline Start/End via headless isolate, colors + drawables.
- **Phase 2 — Food + Expense:** providers + layouts, AppShell deep-link routing.
- **Phase 3 — Weight + Quests:** provider + layout, weight deep-link, optional inline quest-complete.

## RPG Impact
XP/HP/streak only via existing presenter methods (`stopFast`, `completeQuest`) — no new math, no
direct `addXp`. Inline mutations mark the right `SyncDomain` dirty. Start/End fast reschedules the
fasting alarm + ticker via the existing presenter → `NotificationService` flow.

## Risks
- Headless isolate can't cheaply rebuild the full presenter graph / lacks auth → build a minimal
  graph re-scoped from `widget.lastUserId`; fallback = `widget.pendingActions` queue drained on
  foreground.
- Glance staleness while killed (acceptable; only Chronometer stays live).
- Shared-device privacy → must clear snapshot on sign-out (test it).
- Light/dark drift in the manual native color mirror.

## Acceptance Criteria
- [ ] Four widgets installable; reflect in-app changes within ~1s.
- [ ] Fasting Chronometer ticks with app killed.
- [ ] Start/End fast + complete quest mutate real state and sync.
- [ ] Food/Expense/Weight deep-link correctly.
- [ ] Sign-out clears snapshot; second account sees nothing of the first.
- [ ] `dart format` clean; bridge unit test green.

## Out of scope (future)
iOS WidgetKit; background periodic refresh while killed; configurable widgets.
