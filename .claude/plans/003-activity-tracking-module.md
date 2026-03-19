# Feature Implementation Plan: Activity Tracking Module (Training Grounds)

> Status: DRAFT — awaiting approval
> Created: 2026-03-20

---

## Feature Name
Activity Tracking Module — "Training Grounds"

## Goal
Track daily steps and physical activity, pulling data automatically from **Android Health Connect** (the modern replacement for Google Fit, built into Android 14+). Hitting your daily step goal awards XP and boosts **AGI** (Agility) — the stat tied to movement and physical discipline. Falls back gracefully to manual step entry if Health Connect is unavailable or permission is denied.

## Spec Reference
No existing spec — create `docs/activity_spec.md` as part of this feature.

---

## Health Connect Integration Overview

**What it is:** Android's unified health data platform. Replaces Google Fit. Built into Android 14+, available as a downloadable app on Android 9–13.

**Flutter package:** `health: ^12.x.x` (pub.dev) — wraps Health Connect (Android) and HealthKit (iOS) in one API. We only care about Android for now.

**Data we read (read-only, no writing needed):**
- `HealthDataType.STEPS` — step count for a time range
- `HealthDataType.ACTIVE_ENERGY_BURNED` — active calories (bonus display, not required)
- `HealthDataType.DISTANCE_DELTA` — distance walked in meters (bonus display, not required)

**Permissions needed in `AndroidManifest.xml`:**
```xml
<!-- Health Connect read permissions -->
<uses-permission android:name="android.permission.health.READ_STEPS"/>
<uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED"/>
<uses-permission android:name="android.permission.health.READ_DISTANCE"/>

<!-- Required: let Health Connect query our app -->
<queries>
  <package android:name="com.google.android.apps.healthdata" />
</queries>

<!-- Required: Health Connect privacy policy activity -->
<activity android:name="io.flutter.plugins.health.HealthDataActivity" ... />
```

**Permission flow:**
- App checks if Health Connect is available (`health.isHealthConnectAvailable()`)
- If yes: requests permissions via `health.requestAuthorization([...])`
- Health Connect shows its own system permission dialog
- If denied or unavailable: fall back to manual entry mode

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/activity_log.dart` | **Create** | Model |
| `lib/models/activity_goals.dart` | **Create** | Model |
| `lib/presenters/activity_presenter.dart` | **Create** | Presenter |
| `lib/services/storage_service.dart` | Modify — add activity keys + methods | Service |
| `lib/services/health_service.dart` | **Create** — Health Connect abstraction | Service |
| `lib/views/activity/activity_screen.dart` | **Create** — main module screen | View |
| `lib/views/activity/activity_permission_screen.dart` | **Create** — permission onboarding | View |
| `lib/views/hub_screen.dart` | Modify — unlock Training Grounds card | View |
| `android/app/src/main/AndroidManifest.xml` | Modify — add Health Connect permissions | Native |
| `pubspec.yaml` | Modify — add `health` package | Config |

*Note: Hub screen changes depend on plan 001 (nav overhaul) being implemented first.*

---

## Interface Definitions

```dart
// === Model: ActivityLog ===
// Represents one day's activity summary
class ActivityLog {
  final String date;          // 'yyyy-MM-dd'
  final int steps;            // total steps for the day
  final double? activeCalories;
  final double? distanceMeters;
  final bool isManualEntry;   // true if user typed it in vs Health Connect

  const ActivityLog({...});
  factory ActivityLog.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
  ActivityLog copyWith({int? steps, ...});
}

// === Model: ActivityGoals ===
class ActivityGoals {
  final int dailyStepGoal;    // default: 8000

  const ActivityGoals({required this.dailyStepGoal});
  factory ActivityGoals.initial();
  factory ActivityGoals.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

// === StorageService additions ===
static const String keyActivityLogs = 'activityLogs';
static const String keyActivityGoals = 'activityGoals';

Future<void> saveActivityLog(ActivityLog log);
Future<ActivityLog?> loadTodayActivityLog();
Future<List<ActivityLog>> loadActivityHistory();     // last 30 days
Future<void> saveActivityGoals(ActivityGoals goals);
Future<ActivityGoals> loadActivityGoals();

// === HealthService (new service — wraps `health` package) ===
class HealthService {
  Future<bool> isAvailable();
  Future<bool> requestPermissions();
  Future<bool> hasPermissions();
  Future<int> readTodaySteps();
  Future<double?> readTodayActiveCalories();
  Future<double?> readTodayDistance();
}

// === ActivityPresenter public API ===
class ActivityPresenter extends ChangeNotifier {
  ActivityPresenter({
    required StatsPresenter statsPresenter,
    required HealthService healthService,
  });

  // State
  ActivityLog get todayLog;
  ActivityGoals get goals;
  List<ActivityLog> get history;
  bool get isHealthConnectAvailable;
  bool get hasHealthPermission;
  bool get isLoading;

  // Computed getters — safe for build()
  int get todaySteps;                         // shorthand: todayLog.steps
  double get stepProgress;                    // 0.0–1.0 (can exceed 1.0)
  bool get isGoalMet;
  String get summaryLabel;                    // "6,240 / 8,000 steps"

  // Actions
  Future<void> loadState();
  Future<void> syncFromHealthConnect();       // pull today's steps from HC
  Future<void> setManualSteps(int steps);     // fallback manual entry
  Future<void> updateGoals(ActivityGoals goals);
  Future<void> requestHealthPermission();

  // Internal RPG hook
  void _onGoalMet();  // +XP + AGI via StatsPresenter
}
```

---

## Implementation Order

1. [ ] Add `health` package to `pubspec.yaml`
2. [ ] Add Health Connect permissions to `AndroidManifest.xml`
3. [ ] Create `ActivityLog` and `ActivityGoals` models
4. [ ] Add storage keys + methods to `StorageService`
5. [ ] Create `HealthService` — thin wrapper around the `health` package
6. [ ] Implement `ActivityPresenter` — sync logic, fallback, RPG hooks
7. [ ] Build `ActivityPermissionScreen` — explains why we need Health Connect, shows grant button
8. [ ] Build `ActivityScreen` — step ring, today summary, sync button, history list
9. [ ] Wire into `HubScreen` — unlock Training Grounds card
10. [ ] UX verification

---

## Screen Layout: ActivityScreen

```
AppBar: "Training Grounds"  [history icon]  [settings/goal icon]

─── Step Ring ─────────────────────────────────────
        6,240
      ┌──────┐
     /  ████  \   78% of goal
    |   ████   |
     \  ████  /
      └──────┘
     8,000 step goal

  Active Calories: 340 kcal   Distance: 4.8 km
───────────────────────────────────────────────────

─── Health Connect Status ─────────────────────────
  [✓ Synced 5 min ago]   [Sync Now]
  — OR —
  [⚠ Health Connect not connected]  [Connect]
  — OR —
  [Manual mode]  [Enter steps manually]
───────────────────────────────────────────────────

─── Recent Days ───────────────────────────────────
  Yesterday   8,432  ✓ Goal met
  Mar 18      5,100
  Mar 17      9,200  ✓ Goal met
───────────────────────────────────────────────────
```

---

## Hub Card Summary
The `ModuleCard` subtitle from `ActivityPresenter`:
- No data / not synced → `"Tap to connect Health"`
- In progress → `"6,240 / 8,000 steps"`
- Goal met → `"8,432 steps ✓"`

---

## RPG Impact

- **XP awarded:** 25 XP the first time daily step goal is met each day
- **Stat affected:** +1 AGI point every 5 consecutive days goal is met
- **Streak:** Tracked inside `ActivityPresenter` — separate from fasting streak
- **Notifications:** Optional phase 2 — "You're at 5,000 steps, almost there!"
- **Health Connect sync:** Triggered on app open (background refresh) + manual sync button

---

## Risks

| Risk | Mitigation |
|---|---|
| Health Connect not installed (Android 9–13 users) | `isAvailable()` check; prompt user to install from Play Store with a link; fallback to manual entry |
| User denies Health Connect permission | Show `ActivityPermissionScreen` explaining the benefit; always offer manual entry as escape hatch |
| `health` package version compatibility with `minSdkVersion` | Check current `build.gradle` — `health` requires minSdk ≥ 26 (Android 8.0). Verify before adding. |
| Step data granularity — Health Connect returns aggregated data, not real-time | Read total steps for today's date range (midnight to now) — sufficient for our use case |
| Duplicate XP if user syncs multiple times after goal met | Track `_goalMetDate` in presenter state; only award XP once per calendar day |
| Background sync battery drain | Do NOT use background fetch — sync only on app open and manual tap |

---

## UX Verification

- [ ] Primary CTA (Sync / Connect button) in bottom 30% of screen or clearly visible
- [ ] All touch targets ≥ 44×44px
- [ ] Step ring animation on load/sync: 300ms fill animation
- [ ] No animation > 400ms
- [ ] Health Connect status (connected / disconnected / manual) glanceable in < 1 second
- [ ] Manual entry fallback always accessible — no dead ends if HC unavailable
- [ ] Permission rationale screen explains benefit before showing system dialog

---

## Acceptance Criteria

- [ ] `health` package added and app compiles with Health Connect permissions
- [ ] On first open: permission onboarding screen shown if HC available but not granted
- [ ] Steps read from Health Connect and displayed on `ActivityScreen`
- [ ] Manual step entry works when HC is unavailable or permission denied
- [ ] Sync button refreshes step count from Health Connect
- [ ] Daily step goal configurable by user
- [ ] Progress ring reflects step count vs goal in real time
- [ ] First time goal met each day: +25 XP awarded via `StatsPresenter`
- [ ] Hub card subtitle shows live step count
- [ ] Past 30 days of activity visible in history list
- [ ] No logic in any `build()` method
- [ ] Data persists across app restarts
