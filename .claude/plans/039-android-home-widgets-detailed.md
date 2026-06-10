# Plan 039 — Android Home-Screen Widgets (Core Logging Glances + Quick Actions)

> Platform: **Android now, iOS later** (the Dart bridge is architected so a WidgetKit extension
> can be added in a follow-up without reworking the data layer).
> Interaction: **inline quick-actions where safe** (Start/End fast, complete quest) + **deep-link**
> for richer flows (food / expense entry).

## Goal
Put The System on the home screen. Glanceable widgets for the four core loops — **fasting timer,
food logging, expense logging, weight + quests** — so the user feels the RPG pull without opening
the app, and can fire the highest-value actions (start/end a fast, complete a quest) in one tap.

Why it matters to the loop: the daily pull is fasting streaks, calorie/protein goals, and quest
completion. A home-screen presence is a persistent, zero-friction nudge — the strongest retention
lever we can add short of notifications, and it compounds with them.

---

## Conflict Check

| Check | Finding |
|---|---|
| **File overlap** | None. We **read** existing presenters and **add** a new `WidgetBridgeService` + native files. Only light edits to `main.dart`, `home_screen.dart` (AppShell), `MainActivity.kt`, `AndroidManifest.xml`. Plan 038 (grocery cart) touches Treasury/Ledger UI — no shared files. Plan 037 touches `nutrition_presenter.dart` — we only read its getters, no logic change. |
| **Model overlap** | New `WidgetSnapshot` model is widget-only. No clash. |
| **StorageService keys** | New keys are **device-level / unscoped** (widget snapshot must survive without a userId). No clash with user-scoped keys. |
| **XP routing** | Inline actions call existing presenter methods (`startFast`/`stopFast`/`completeQuest`) which already route XP through `StatsPresenter`. **No direct `addXp`.** Plan 008 already merged. |
| **HubScreen** | Not unlocking a hub card. N/A. |
| **Supersedes** | None. |
| **Dependency order** | Standalone. No blocking plans. |

---

## The central constraint (read this first)

`LocalStorageService` prefixes **all** user data with `u/$userId/`, set only after auth. The native
widget runs in a separate process (and, for inline actions, a headless Flutter isolate) that has **no
auth session and no userId**. Three consequences drive the whole design:

1. **Widgets never read app prefs directly.** The app **pushes** a small denormalized `WidgetSnapshot`
   into `home_widget`'s own prefs group (unscoped, namespaced `widget.*`). The native layout renders
   only from that snapshot. This is also the privacy boundary on shared devices.
2. **Sign-out must clear the snapshot.** Per [[project_signout_wipes_local]], local data is wiped on
   sign-out. The bridge clears `widget.*` and re-pushes an "empty / sign in" state so a second user
   never sees the first user's numbers.
3. **The fasting timer must tick without the Flutter process.** We reuse the proven notification
   trick: store `fastStartMillis` + `targetMillis` and render with a **native Android `Chronometer`**
   (`RemoteViews`), which counts up/down on its own — no background isolate, no battery cost.

---

## Architecture overview

```
┌─ Flutter (app process) ─────────────────────────────┐
│  Presenters (Fasting/Nutrition/Ledger/Quest/Stats)  │
│        │ ChangeNotifier                              │
│        ▼                                             │
│  WidgetBridgeService  ── listens to all 5 ──┐        │
│    • builds WidgetSnapshot (denormalized)   │        │
│    • debounced HomeWidget.saveWidgetData()  │        │
│    • HomeWidget.updateWidget(...)           │        │
└─────────────────────────────────────────────┼───────┘
                                               ▼
                          home_widget prefs group (unscoped)
                                               │
┌─ Native Android (widget process) ────────────┼───────┐
│  *WidgetProvider (RemoteViews) renders snapshot       │
│  Chronometer ticks fasting time natively              │
│  Taps →                                               │
│    • deep-link Intent  → MainActivity (food/expense)  │
│    • interactive action → headless Dart callback      │
│         (start/end fast, complete quest)              │
└───────────────────────────────────────────────────────┘
```

**Inline-action safety rule:** a tap runs an inline action **only if** it is purely local (no network,
no AI, no rich UI). Start fast, end fast, complete quest qualify. Food parse (AI) and expense
categorisation do **not** → those deep-link into the app.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `pubspec.yaml` | Modify — add `home_widget` | Deps |
| `lib/models/widget/widget_snapshot.dart` | Create — denormalized snapshot model | Model |
| `lib/services/widget_bridge_service.dart` | Create — listens to presenters, pushes snapshot, handles deep-link + interactive routing | Service |
| `lib/services/storage_service.dart` (+ `local_storage_service.dart`) | Modify — device-level keys for last-known userId + "pending widget action" queue | Service |
| `lib/main.dart` | Modify — register `@pragma('vm:entry-point')` background callback; handle launch deep-link | Entry |
| `lib/views/home_screen.dart` (AppShell) | Modify — construct `WidgetBridgeService`, wire it to presenters, route incoming deep-links to the right screen, clear snapshot on sign-out | View/wiring |
| `android/app/src/main/kotlin/com/nudgr/app/MainActivity.kt` | Modify — parse widget deep-link intents (singleTop `onNewIntent` + cold start) | Native |
| `android/app/src/main/AndroidManifest.xml` | Modify — register widget providers, receivers, deep-link intent-filter | Native |
| `android/app/src/main/res/xml/widget_*_info.xml` | Create — `appwidget-provider` configs (sizes, resize, preview) | Native |
| `android/app/src/main/res/layout/widget_*.xml` | Create — RemoteViews layouts per widget | Native |
| `android/app/src/main/res/values/colors.xml` + `values-night/colors.xml` | Create — Solo-Leveling token mirror (dark) + light | Native |
| `android/app/src/main/res/drawable/widget_bg*.xml` | Create — rounded card backgrounds, ring drawables | Native |
| `android/app/src/main/kotlin/.../*WidgetProvider.kt` | Create — one provider per widget | Native |
| `test/services/widget_bridge_service_test.dart` | Create — snapshot mapping + sign-out clear | Test |

> **Theming note:** native widgets cannot read `Theme.of(context)` (CLAUDE.md rule #7 governs Flutter
> widgets). Android day/night is handled by `values/` vs `values-night/` resource qualifiers. We mirror
> the relevant `AppColors` (dark) and `AppColorsLight` (light) tokens into `colors.xml` once and keep
> them in sync manually. Document this in the file header so it isn't mistaken for a rule violation.

---

## Interface Definitions

```dart
// === Model: lib/models/widget/widget_snapshot.dart ===
// One flat object the app pushes to home_widget prefs. Every field is a primitive/String
// so it round-trips through HomeWidget.saveWidgetData<T>() with no nested JSON on the native side.
class WidgetSnapshot {
  final bool signedIn;            // false → all widgets show "Sign in" empty state

  // Fasting
  final bool isFasting;
  final int? fastStartMillis;     // epoch — feeds native Chronometer base
  final int? targetMillis;        // epoch of goal end (for countdown variant)
  final int fastingGoalHours;
  final int currentStreak;
  final String fastPhaseLabel;    // e.g. "Ketosis" — precomputed, no calc on native side

  // Food
  final int todayCalories;
  final int calorieGoal;          // effectiveGoal
  final int proteinGrams;
  final int? proteinGoal;

  // Expense
  final String monthOutflowLabel; // currency-formatted in Dart
  final String todayOutflowLabel;

  // Weight
  final String? latestWeightLabel; // "72.4 kg" / "159 lb" — unit-aware, formatted in Dart
  final String? weightDeltaLabel;

  // Quests
  final int questsDoneToday;
  final int questsTotalToday;
  final String? nextQuestLabel;
  final bool hasUrgentQuest;

  Map<String, Object?> toWidgetData(); // flat key→value for HomeWidget.saveWidgetData
  static WidgetSnapshot empty();        // signedIn=false
}

// === StorageService additions (DEVICE-LEVEL / UNSCOPED) ===
static const String keyWidgetLastUserId = 'widget.lastUserId';   // for headless isolate to re-scope
static const String keyWidgetPendingActions = 'widget.pendingActions'; // fallback queue (see Risks)
Future<String?> loadWidgetLastUserId();
Future<void> saveWidgetLastUserId(String? userId);

// === WidgetBridgeService (lib/services/widget_bridge_service.dart) ===
class WidgetBridgeService {
  WidgetBridgeService({
    required StorageService storage,
    required FastingPresenter fasting,
    required NutritionPresenter nutrition,
    required LedgerPresenter ledger,
    required QuestPresenter quests,
  });

  void attach();   // adds listeners to all presenters (debounced push)
  void detach();   // removes listeners

  Future<void> pushSnapshot();          // build + saveWidgetData + updateWidget (debounced ~500ms)
  Future<void> clearForSignOut();       // push WidgetSnapshot.empty(), wipe widget.* keys

  // Deep-link routing (called from AppShell on launch/resume intent)
  static WidgetRoute? parseLaunchUri(Uri? uri);  // nudgr://food, nudgr://expense, ...

  // Inline interactive callback (headless isolate entry — registered in main.dart)
  @pragma('vm:entry-point')
  static Future<void> onInteractiveAction(Uri? uri);  // start/end fast, complete quest
}

enum WidgetRoute { fasting, foodLog, expenseAdd, weightLog, quests }
```

**Deep-link scheme** (no scheme exists today — we add the first intent-filter):
```
nudgr://food        → push NutritionScreen, open quick-log
nudgr://expense     → push Treasury ledger, open add-transaction sheet
nudgr://weight      → push WeightLogScreen, focus entry
nudgr://fasting     → push TimerTab
nudgr://quests      → push QuestsTab
```

---

## Widgets (visual spec, per MVP scope)

1. **Fasting (flagship)** — ring/progress bar + native `Chronometer` (elapsed or countdown),
   phase label, streak. Buttons: **Start Fast** / **End Fast** (inline, local-only). Sizes: 2×1 (timer
   + 1 action) and 2×2 (adds streak + phase + ring).
2. **Food** — `todayCalories / calorieGoal` with a thin progress bar + protein chip. Tap → `nudgr://food`.
3. **Expense** — month spend (big), today spend (small). Tap → `nudgr://expense`.
4. **Weight + Quests (combined 2×2, or two 2×1s)** — latest weight + delta (tap → `nudgr://weight`);
   quests `done/total` + next quest label, urgent state in accent. Optional inline **✓ complete next quest**.

All four read from the **same** snapshot; `updateWidget` refreshes whichever providers are placed.

---

## Implementation Order

**Phase 0 — Foundation (no user-visible widget yet)**
1. [ ] Add `home_widget` to `pubspec.yaml`; `flutter pub get`.
2. [ ] Create `WidgetSnapshot` model + `toWidgetData()` / `empty()`.
3. [ ] Add device-level storage keys (`widget.lastUserId`) + persist userId on auth in AppShell.
4. [ ] Create `WidgetBridgeService`: build snapshot from presenter getters, debounced push.
5. [ ] Wire bridge in AppShell `initState` (after presenters built) + `attach()`; persist last userId;
       `clearForSignOut()` on the existing sign-out path.
6. [ ] Native plumbing: manifest providers + a single shared "no-op" placeholder layout to prove the
       data round-trip end to end before styling.

**Phase 1 — Fasting widget (flagship)**
7. [ ] `FastingWidgetProvider.kt` + `widget_fasting.xml` with native `Chronometer` bound to
       `fastStartMillis` / `targetMillis`. Verify it ticks with the app **killed**.
8. [ ] Deep-link intent-filter + `MainActivity.kt` intent parsing (cold start + `onNewIntent`).
9. [ ] Inline Start/End: register `@pragma('vm:entry-point') onInteractiveAction`; headless isolate
       re-scopes storage via `widget.lastUserId`, calls `startFast()`/`stopFast()`, re-pushes snapshot,
       reschedules the fasting notification/alarm (reuse `NotificationService` path).
10. [ ] colors.xml (+ night) token mirror; ring/bg drawables.

**Phase 2 — Food + Expense widgets**
11. [ ] `FoodWidgetProvider` + layout (calories/goal bar, protein chip) → `nudgr://food`.
12. [ ] `ExpenseWidgetProvider` + layout (month/today spend) → `nudgr://expense`.
13. [ ] AppShell deep-link routing → NutritionScreen quick-log / Treasury add-transaction sheet.

**Phase 3 — Weight + Quests**
14. [ ] `WeightQuestWidgetProvider` + layout. Weight → `nudgr://weight`.
15. [ ] Quests glance (done/total, next, urgent accent); optional inline ✓ via `onInteractiveAction`
        (`completeQuest`), guarded by the same local-only rule.

---

## RPG Impact
- **XP/HP:** Only via existing presenter methods invoked inline (`stopFast` returns XP/HP; `completeQuest`
  returns XP + crit). No new XP math. Headless isolate marks the right `SyncDomain` dirty (existing
  `_markDirty`) so the action syncs on next app open.
- **Streaks:** `startFast`/`stopFast`/`completeQuest` already manage streaks — unchanged.
- **Notifications:** End/Start fast from the widget must reschedule/cancel the fasting alarm + persistent
  ticker exactly as the in-app buttons do (reuse the presenter→NotificationService flow).

## Risks
- **Headless isolate cannot reconstruct the full presenter graph cheaply / lacks auth.** Mitigation:
  inline actions are local-only; the isolate builds a **minimal** graph (`LocalStorageService` re-scoped
  from `widget.lastUserId` → `StatsPresenter` → the one presenter needed). If reconstruction proves
  fragile, **fallback**: write the action to `widget.pendingActions`, optimistically update the snapshot,
  and let AppShell drain the queue on next foreground (delays XP/notification but never corrupts state).
  Decide during Phase 1 spike — keep the fallback queue as the safety net.
- **Snapshot staleness while app is killed.** Glance numbers freeze until next app open (acceptable);
  only the fasting Chronometer stays live (native). Document the tradeoff; no background polling in MVP.
- **Shared-device privacy.** Must verify `clearForSignOut()` wipes `widget.*` and re-renders empty —
  otherwise user B sees user A's data. Explicit test + manual check. ([[project_signout_wipes_local]])
- **Light/dark drift.** Native colors are a manual mirror of `AppColors`/`AppColorsLight`; add a header
  comment + a checklist item so token changes propagate. ([[project_dual_theme]])
- **`minSdk 26`** is fine for App Widgets; inline buttons use `RemoteViews` + `PendingIntent`
  (Glance optional, not required for MVP).

## UX Verification
- [ ] Glanceable status readable in < 1 second (numbers + ring, no scrolling).
- [ ] Inline buttons ≥ 44×44px tap target in the RemoteViews layout.
- [ ] Fasting Chronometer ticks with app force-killed.
- [ ] Deep-links land on the correct screen from both cold start and warm resume (singleTop).
- [ ] Empty/sign-in state shows when signed out; no stale numbers after sign-out.
- [ ] Dark + light widget backgrounds both legible (values vs values-night).

## Acceptance Criteria
- [ ] Four widgets installable from the launcher picker (fasting, food, expense, weight+quests).
- [ ] All render live data pushed by `WidgetBridgeService` within ~1s of an in-app change.
- [ ] Start/End fast from the widget mutates real state, updates XP/HP/streak, reschedules the alarm,
      and reflects in-app on next open.
- [ ] Food/Expense/Weight taps deep-link to the correct logging entry point.
- [ ] Sign-out clears the snapshot; a second account never sees the first account's data.
- [ ] `dart format` clean; bridge unit test green. ([[feedback_format_check]])

## Out of scope (future)
- iOS WidgetKit extension (the Dart bridge + snapshot model are designed to feed it later).
- Background periodic refresh of glance numbers while app is killed (would need WorkManager).
- Configurable widgets (which account/quest to show) — fixed defaults in MVP.
```

