# Plan 011 — Full App Test Suite

> Status: DRAFT — awaiting approval
> Created: 2026-03-25

---

## Goal

Build a regression test suite covering every layer of the MVP architecture. No device or emulator needed for the bulk of tests — unit tests cover all business logic and RPG math; widget tests cover key screens; a small integration smoke test validates the real device flow. This protects the RPG loop (XP, HP, streaks, stat awards) from silent breakage as features are added.

---

## Scope

### What we test

| Layer | Approach | Speed |
|---|---|---|
| Models | Unit — `fromJson`/`toJson` round-trips, validation | Instant |
| StorageService | Unit — fake SharedPreferences (`shared_preferences_platform_interface`) | Instant |
| HealthService | Unit — mock `Health()` via Mockito | Instant |
| StatsPresenter | Unit — mock StorageService | Instant |
| FastingPresenter | Unit — mock StorageService + NotificationService + StatsPresenter | Instant |
| ActivityPresenter | Unit — mock HealthService + StorageService + StatsPresenter | Instant |
| NutritionPresenter | Unit — mock all services + StatsPresenter | Instant |
| Key widgets | Widget test — pump screen, find, tap, verify rebuild | Fast |
| Smoke / regression | Integration test — real device, happy path per module | Slow |

### What we skip (for now)
- `FoodDbService` (SQLite asset copy — integration only)
- `AiEstimationService` (requires on-device model)
- `NotificationService` (OS-level scheduling — mocked at boundary)

---

## New Files

```
test/
  models/
    activity_log_test.dart
    activity_goals_test.dart
    fasting_log_test.dart
    user_stats_test.dart
    daily_nutrition_log_test.dart
    nutrition_goals_test.dart
    food_entry_test.dart
  services/
    storage_service_test.dart        ← uses FakeSharedPreferences
    health_service_test.dart         ← mocks Health()
  presenters/
    stats_presenter_test.dart
    fasting_presenter_test.dart
    activity_presenter_test.dart
    nutrition_presenter_test.dart
  views/
    hub_screen_test.dart
    activity_screen_test.dart
    timer_tab_test.dart
  integration_test/
    app_smoke_test.dart              ← requires device
```

---

## Dependencies to add

```yaml
# pubspec.yaml dev_dependencies
dev_dependencies:
  mockito: ^5.4.4
  build_runner: ^2.4.9
  fake_async: ^1.3.1
```

`mockito` generates mock classes from `@GenerateMocks([...])` annotations via `build_runner`.

---

## Interface Definitions — Mock Classes Needed

```dart
// Run: dart run build_runner build
@GenerateMocks([
  StorageService,
  HealthService,
  StatsPresenter,
  FastingPresenter,
  NotificationService,
])
```

Each test file imports its generated `.mocks.dart` file.

---

## Test Strategy by Layer

### 1. Models — `test/models/`

All models are pure Dart — no mocking needed.

**Pattern for every model:**
```dart
group('ActivityLog', () {
  test('round-trips through JSON', () {
    final log = ActivityLog(date: '2026-03-25', steps: 6240, isManualEntry: true);
    expect(ActivityLog.fromJson(log.toJson()), equals(log));  // needs ==
  });

  test('empty() has zero steps', () {
    expect(ActivityLog.empty('2026-03-25').steps, 0);
  });

  test('copyWith preserves unchanged fields', () {
    final log = ActivityLog(date: '2026-03-25', steps: 100);
    final updated = log.copyWith(steps: 200);
    expect(updated.steps, 200);
    expect(updated.date, '2026-03-25');
  });
});
```

**Models to cover:** `ActivityLog`, `ActivityGoals`, `FastingLog`, `UserStats`, `DailyNutritionLog`, `NutritionGoals`, `FoodEntry`, `Quest`.

*Note: Models need `==` and `hashCode` overrides (or use `equatable`) for `expect(a, equals(b))` to work. Plan to add these.*

---

### 2. StorageService — `test/services/storage_service_test.dart`

Use `SharedPreferences.setMockInitialValues({})` (built into Flutter test SDK) — no plugin needed.

```dart
setUp(() => SharedPreferences.setMockInitialValues({}));

test('saveActivityLog and loadTodayActivityLog round-trip', () async {
  final svc = StorageService();
  final log = ActivityLog(date: todayKey(), steps: 5000);
  await svc.saveActivityLog(log);
  final loaded = await svc.loadTodayActivityLog();
  expect(loaded.steps, 5000);
});

test('loadActivityGoals returns initial when empty', () async {
  final svc = StorageService();
  final goals = await svc.loadActivityGoals();
  expect(goals.dailyStepGoal, 8000);
});
```

Cover: activity, nutrition, fasting state, user stats round-trips.

---

### 3. StatsPresenter — `test/presenters/stats_presenter_test.dart`

```dart
late MockStorageService mockStorage;
late StatsPresenter presenter;

setUp(() {
  mockStorage = MockStorageService();
  when(mockStorage.loadUserStats()).thenAnswer((_) async => UserStats.initial());
  presenter = StatsPresenter(mockStorage);
});

test('addXp awards XP and levels up at threshold', () async {
  // Level 1 requires 100 XP
  await presenter.addXp(100);
  expect(presenter.stats.level, 2);
  expect(presenter.showLevelUpDialog, true);
});

test('awardStat increments AGI', () async {
  final before = presenter.stats.attributes.agi;
  await presenter.awardStat('agi');
  expect(presenter.stats.attributes.agi, before + 1);
});

test('modifyHp clamps to maxHp', () async {
  await presenter.modifyHp(9999);
  expect(presenter.stats.currentHp, presenter.maxHp);
});
```

---

### 4. ActivityPresenter — `test/presenters/activity_presenter_test.dart`

Most important RPG math to protect:

```dart
// Given: steps reach goal for the first time today
// When: setManualSteps(8000)
// Then: statsPresenter.addXp(25) called once
test('awards 25 XP first time goal met today', () async {
  when(mockStorage.loadActivityGoalMetDate()).thenAnswer((_) async => null);
  when(mockStorage.loadActivityStreak()).thenAnswer((_) async => 0);
  await presenter.setManualSteps(8000);
  verify(mockStats.addXp(25)).called(1);
});

// Given: goal met but goalMetDate == today already
// When: setManualSteps again
// Then: addXp NOT called again
test('does not double-award XP on same day', () async {
  when(mockStorage.loadActivityGoalMetDate()).thenAnswer((_) async => todayKey());
  await presenter.setManualSteps(8000);
  verifyNever(mockStats.addXp(any));
});

// Given: streak is 4 (previous days)
// When: goal met today → streak becomes 5
// Then: awardStat('agi') called
test('awards AGI on 5-day streak', () async {
  when(mockStorage.loadActivityStreak()).thenAnswer((_) async => 4);
  await presenter.setManualSteps(8000);
  verify(mockStats.awardStat('agi')).called(1);
});

// Health Connect unavailable → stepProgress and hubSubtitle still safe
test('hubSubtitle shows connect prompt when no permission', () {
  // HC unavailable by default in mock
  expect(presenter.hubSubtitle, 'Tap to connect Health');
});
```

---

### 5. FastingPresenter — `test/presenters/fasting_presenter_test.dart`

Critical RPG paths:

```dart
// stopFast — success path
test('successful fast awards XP and heals HP', () async {
  presenter.isFasting = true;
  presenter.startTime = DateTime.now().subtract(Duration(hours: 17));
  final (xp, hp) = await presenter.stopFast();
  expect(xp, greaterThan(0));
  expect(hp, greaterThan(0));
  verify(mockStats.addXp(any)).called(1);
  verify(mockStats.incrementStreak()).called(1);
});

// stopFast — failure path
test('early stop deals damage and resets streak', () async {
  presenter.isFasting = true;
  presenter.startTime = DateTime.now().subtract(Duration(hours: 8));
  final (_, hp) = await presenter.stopFast();
  expect(hp, lessThan(0));
  verify(mockStats.resetStreak()).called(1);
});

// Quest completion XP
test('completeQuest awards XP once per day', () async {
  await presenter.addQuest('Test', 8, 0, List.filled(7, true));
  final xp1 = await presenter.completeQuest(0);
  final xp2 = await presenter.completeQuest(0); // second tap same day
  expect(xp1, greaterThan(0));
  expect(xp2, 0); // no double XP
});
```

---

### 6. NutritionPresenter — `test/presenters/nutrition_presenter_test.dart`

```dart
// Calorie goal met → +30 XP, +10 if IF sync
test('calorie goal met awards 30 XP', () async {
  when(mockStorage.loadNutritionGoalMetDate()).thenAnswer((_) async => null);
  await presenter.addFoodEntry(entry2000kcal, MealSlot.breakfast);
  verify(mockStats.addXp(30)).called(1);
});

// Protein goal → +15 XP + STR
test('protein goal met awards 15 XP and STR', () async {
  // goals.proteinGrams = 150, entry has 150g protein
  await presenter.addFoodEntry(highProteinEntry, MealSlot.lunch);
  verify(mockStats.addXp(15)).called(1);
  verify(mockStats.awardStat('str')).called(1);
});

// Overshoot penalty
test('overshoot applies -5 HP when enabled', () async {
  // goals.overshootPenaltyEnabled = true, goal = 2000, entry = 2500
  await presenter.addFoodEntry(entry2500kcal, MealSlot.dinner);
  verify(mockStats.modifyHp(-5)).called(1);
});

// IF sync blocks logging during fast
test('blocks entry during fast when IF sync enabled', () async {
  when(mockFasting.isFasting).thenReturn(true);
  // goals.ifSyncEnabled = true
  await presenter.addFoodEntry(anyEntry, MealSlot.breakfast);
  expect(presenter.todayCalories, 0);
});
```

---

### 7. Widget Tests — `test/views/`

**HubScreen** — verify module cards render correctly:
```dart
testWidgets('Training Grounds card shows step subtitle', (tester) async {
  await tester.pumpWidget(
    MaterialApp(home: HubScreen(
      fastingPresenter: mockFasting,
      statsPresenter: mockStats,
      activityPresenter: mockActivity,  // hubSubtitle = '6,240 / 8,000 steps'
    )),
  );
  expect(find.text('6,240 / 8,000 steps'), findsOneWidget);
});

testWidgets('Training Grounds locked when activityPresenter null', (tester) async {
  await tester.pumpWidget(MaterialApp(home: HubScreen(..., activityPresenter: null)));
  expect(find.text('LOCKED'), findsWidgets); // or check ModuleCard isLocked rendering
});
```

**ActivityScreen** — ring and sync:
```dart
testWidgets('displays step count and goal', (tester) async {
  // presenter.todaySteps = 4000, goals.dailyStepGoal = 8000
  await tester.pumpWidget(MaterialApp(home: ActivityScreen(presenter: mockPresenter)));
  expect(find.text('4,000'), findsOneWidget);
  expect(find.text('4,000 / 8,000 steps'), findsOneWidget);
});

testWidgets('tapping Sync Now calls syncFromHealthConnect', (tester) async {
  // presenter.hasHealthPermission = true
  await tester.pumpWidget(...);
  await tester.tap(find.text('Sync Now'));
  verify(mockPresenter.syncFromHealthConnect()).called(1);
});
```

**TimerTab** — start/stop fast:
```dart
testWidgets('Start Fast button calls startFast', (tester) async {
  // isFasting = false
  await tester.pumpWidget(...);
  await tester.tap(find.text('Start Fast'));
  verify(mockFasting.startFast()).called(1);
});
```

---

### 8. Integration Smoke Test — `integration_test/app_smoke_test.dart`

Requires `flutter_test` + `integration_test` package. Runs on device/emulator.

```dart
testWidgets('hub loads and shows all module cards', (tester) async {
  app.main();
  await tester.pumpAndSettle();
  expect(find.text('DISCIPLINE PROTOCOL'), findsOneWidget);
  expect(find.text('ALCHEMY LAB'), findsOneWidget);
  expect(find.text('TRAINING GROUNDS'), findsOneWidget);
});

testWidgets('manual step entry persists across pump', (tester) async {
  app.main();
  await tester.pumpAndSettle();
  // Tap Training Grounds → Enter Steps → type 5000 → Save → verify display
  await tester.tap(find.text('TRAINING GROUNDS'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Enter Steps'));
  await tester.enterText(find.byType(TextField), '5000');
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  expect(find.text('5,000'), findsOneWidget);
});
```

---

## Implementation Order

1. [ ] Add `mockito`, `build_runner`, `fake_async` to `pubspec.yaml` dev_dependencies
2. [ ] Add `==` / `hashCode` to all models (required for `equals()` assertions)
3. [ ] Create mock generation file `test/mocks.dart` with `@GenerateMocks([...])`
4. [ ] Run `dart run build_runner build` to generate `.mocks.dart`
5. [ ] Write model tests (no mocks needed)
6. [ ] Write StorageService tests (FakeSharedPreferences)
7. [ ] Write StatsPresenter tests
8. [ ] Write ActivityPresenter tests — RPG math first
9. [ ] Write FastingPresenter tests — RPG math first
10. [ ] Write NutritionPresenter tests
11. [ ] Write widget tests (HubScreen, ActivityScreen, TimerTab)
12. [ ] Write integration smoke test
13. [ ] Add `flutter test` to CI / verify all pass

---

## RPG Impact

None — tests are read-only. They protect the RPG math that already exists.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| `FastingPresenter` creates `StorageService` and `NotificationService` internally (not injected) — impossible to mock | Refactor to constructor injection before writing tests (required prerequisite) |
| Models lack `==` override — `expect(a, equals(b))` always fails | Add `==` + `hashCode` to all models in step 2 |
| `health` package uses singleton `Health()` — hard to mock | Wrap behind `HealthService` (already done) — mock `HealthService`, not `Health()` |
| `NutritionPresenter._ai` not easily swappable for test doubles | Already constructor-injected — mock `AiEstimationService` |
| Integration test requires Health Connect on device | Skip HC permission flow in integration test; use manual entry path |

---

## Prerequisite Refactor — FastingPresenter

`FastingPresenter` currently constructs its own services internally:
```dart
// current — untestable
final NotificationService _notificationService = NotificationService();
final StorageService _storageService = StorageService();
```

Must become constructor-injected before tests can be written:
```dart
// required
FastingPresenter({
  required StorageService storage,
  required NotificationService notifications,
  StatsPresenter? statsPresenter,
});
```

`AppShell` passes them in. This is the only code change required before testing — everything else is already injected.

---

## Acceptance Criteria

- [ ] `flutter test` passes with zero failures on fresh clone
- [ ] All RPG XP award paths have a test (`addXp`, `awardStat`, `modifyHp`)
- [ ] All "only once per day" guards tested (XP de-duplication)
- [ ] StorageService round-trips tested for every new model
- [ ] HubScreen renders correct subtitle from each presenter's `hubSubtitle`
- [ ] ActivityScreen manual entry flow tested end-to-end in widget test
- [ ] Integration smoke test verifies app boots and hub renders
- [ ] No logic added to `build()` methods to make tests pass
