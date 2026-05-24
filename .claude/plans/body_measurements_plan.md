# Body Measurements Tracking — Implementation Plan

## Goal

Add a dedicated body measurements log (waist, hips, chest, biceps, thigh) as a
sibling to the existing weight log. Waist is the hero metric — the single strongest
proxy for fat loss progress when the scale isn't moving. The other sites are optional
and user-selected per entry. The system feeds waist trend data into the recomp
detection logic defined in the dashboard rehaul spec.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/body_measurement_entry.dart` | **Create** | Model |
| `lib/models/nutrition_goals.dart` | **Modify** — add `MeasurementUnit` enum + field | Model |
| `lib/utils/body_fat_calculator.dart` | **Create** — pure US Navy formula functions | Utils |
| `lib/services/storage_service.dart` | **Modify** — add keys + 4 abstract methods | Service |
| `lib/services/local_storage_service.dart` | **Modify** — implement new methods | Service |
| `lib/presenters/nutrition_presenter.dart` | **Modify** — measurements, BF%, unit pref, XP | Presenter |
| `lib/views/nutrition/measurement_log_screen.dart` | **Create** | View |
| `lib/views/nutrition/nutrition_history_screen.dart` | **Modify** — add `_MeasurementSection` | View |

---

## Interface Definitions

### Model — `lib/models/body_measurement_entry.dart`

```dart
class BodyMeasurementEntry {
  final String id;           // millisecondsSinceEpoch string
  final DateTime loggedAt;
  final double? waistCm;     // primary — always shown; required for body fat %
  final double? neckCm;      // required for US Navy body fat % formula
  final double? hipsCm;      // required for women's body fat %; optional for men
  final double? chestCm;     // optional
  final double? bicepCm;     // optional (dominant arm or whichever user logs)
  final double? thighCm;     // optional
  final String? notes;       // optional free-text

  // At least one measurement must be non-null — enforced by callers, not model
}
```

- All `double?` fields — user logs only what they have
- `waistCm` is the primary field; the entry is considered "waist-tracked" only if non-null
- `neckCm` + `waistCm` (+ `hipsCm` for women) unlock body fat % estimation
- `fromJson` / `toJson` / `copyWith` following the same shape as `WeightEntry`
- `static String generateId()` → `DateTime.now().millisecondsSinceEpoch.toString()`

### Unit preference — `lib/models/nutrition_goals.dart`

```dart
enum MeasurementUnit { metric, imperial }

// Add to NutritionGoals:
final MeasurementUnit measurementUnit; // default: metric
```

Stored internally always in cm. The presenter converts for display and converts
user input back to cm before saving. Weight log is unaffected (kg-only stays).

### Body fat calculator — `lib/utils/body_fat_calculator.dart`

```dart
// US Navy circumference method — returns body fat % or null if inputs missing.
// For men:   86.010 × log10(waist − neck) − 70.041 × log10(height) + 36.76
// For women: 163.205 × log10(waist + hip − neck) − 97.684 × log10(height) − 78.387
// All inputs in cm.
double? estimateBodyFatPercent({
  required String sex,       // 'male' | 'female'
  required double heightCm,
  required double waistCm,
  required double neckCm,
  double? hipsCm,            // required for female, ignored for male
});
```

Pure function, no state. Returns null when required inputs are absent.

### StorageService additions

```dart
// New keys:
static const String keyBodyMeasurements  = 'bodyMeasurements';
static const String keyMeasurementUnit   = 'measurementUnit';
static const String keyLastRecompXpDate  = 'bodyMeasurements.lastRecompXpDate';

// New abstract methods:
Future<void> saveBodyMeasurements(List<BodyMeasurementEntry> entries);
Future<List<BodyMeasurementEntry>> loadBodyMeasurements();
Future<void> saveMeasurementUnit(MeasurementUnit unit);
Future<MeasurementUnit> loadMeasurementUnit();
Future<void> saveLastRecompXpDate(DateTime date);
Future<DateTime?> loadLastRecompXpDate();
```

Implementations in `LocalStorageService` mirror existing weight log patterns.

### Presenter public API additions (NutritionPresenter)

```dart
// ── Measurement getters ───────────────────────────────────────────────────────

List<BodyMeasurementEntry> get measurementLog;  // chronological, oldest first
BodyMeasurementEntry? get latestMeasurement;    // last entry or null
double? get waistDelta;                         // last-to-prev waist delta in cm
MeasurementTrendDirection get waistTrendDirection; // down|stable|up|insufficient

// ── Unit preference ───────────────────────────────────────────────────────────

MeasurementUnit get measurementUnit;            // metric | imperial
Future<void> setMeasurementUnit(MeasurementUnit unit);

// Formats a cm value for display: "85 cm" or "33.5 in"
String formatMeasurement(double cm);

// Converts display value back to cm for storage (used in entry sheet)
double toStorageCm(double displayValue);

// ── Body fat % ────────────────────────────────────────────────────────────────

// Estimated BF% from latest measurement with waist + neck (+ hips for women).
// Returns null if TdeeProfile missing or required measurements absent.
double? get estimatedBodyFatPercent;

// ── Actions ───────────────────────────────────────────────────────────────────

Future<void> logMeasurement(BodyMeasurementEntry entry);
Future<void> deleteMeasurement(String id);
```

> `MeasurementTrendDirection` — same enum shape as `WeightTrendDirection` from the
> dashboard spec. If the dashboard spec lands first, reuse that enum; otherwise define
> it here and merge later.

---

## Implementation Order

### Step 1 — Model
- [ ] Create `lib/models/body_measurement_entry.dart`
- [ ] Fields: id, loggedAt, waistCm?, neckCm?, hipsCm?, chestCm?, bicepCm?, thighCm?, notes?
- [ ] Implement `fromJson`, `toJson`, `copyWith`, `generateId()`
- [ ] Add `MeasurementUnit` enum to `lib/models/nutrition_goals.dart` + field with default `metric`
- [ ] Unit-test: round-trip JSON with all fields null except waist

### Step 2 — Body fat calculator
- [ ] Create `lib/utils/body_fat_calculator.dart`
- [ ] Implement `estimateBodyFatPercent({sex, heightCm, waistCm, neckCm, hipsCm?})`
- [ ] Return null for invalid inputs (waist ≤ neck, missing required fields)
- [ ] Male formula: `86.010 × log10(waist − neck) − 70.041 × log10(height) + 36.76`
- [ ] Female formula: `163.205 × log10(waist + hip − neck) − 97.684 × log10(height) − 78.387`
- [ ] Clamp result to 3 %–60 % (sanity bounds)

### Step 3 — Storage
- [ ] Add `keyBodyMeasurements`, `keyMeasurementUnit`, `keyLastRecompXpDate` to `StorageService`
- [ ] Add 6 abstract methods (save/load for each new key)
- [ ] Implement all 6 in `LocalStorageService`

### Step 4 — Presenter
- [ ] Add `List<BodyMeasurementEntry> _measurementLog = const []`
- [ ] Add `MeasurementUnit _measurementUnit = MeasurementUnit.metric`
- [ ] Add `DateTime? _lastRecompXpDate`
- [ ] Load all three in `init()`
- [ ] `logMeasurement(entry)`: append → sort → save → `_checkRecompXp()` → `notifyListeners()`
- [ ] `deleteMeasurement(id)`: remove → save → `notifyListeners()`
- [ ] `setMeasurementUnit(unit)`: save → `notifyListeners()`
- [ ] `formatMeasurement(cm)`: returns `"${cm.toStringAsFixed(1)} cm"` or `"${(cm / 2.54).toStringAsFixed(1)} in"`
- [ ] `toStorageCm(displayValue)`: identity for metric, `× 2.54` for imperial
- [ ] `estimatedBodyFatPercent`: calls `BodyFatCalculator.estimateBodyFatPercent` using `latestMeasurement` + `_tdeeProfile`
- [ ] `waistTrendDirection`: filter to waist entries, last 14, first/second-half avg algorithm
- [ ] `_checkRecompXp()`: private — awards XP if recomp confirmed + ≥ 7 days since `_lastRecompXpDate`

### Step 5 — MeasurementLogScreen
Structure mirrors `WeightLogScreen` exactly:

```
AppPageScaffold
  └─ ListView
       ├─ _MeasurementStatsRow   (latest waist · total change · BF% if available)
       ├─ _WaistTrendChart       (CustomPaint — reuse _TrendPainter logic, waist values)
       ├─ _OtherSitesSummary     (collapsed card — latest hips/chest/bicep/thigh if logged)
       └─ _MeasurementEntryList  (newest first, delete swipe)
```

**FAB:** opens `_AddMeasurementSheet`

**`_AddMeasurementSheet`:**
- Primary field: Waist — always visible, autofocus; label is "Waist (cm)" or "Waist (in)" per `measurementUnit`
- "Add more" `ExpansionTile` — reveals neck, hips, chest, bicep, thigh fields (same unit label pattern)
- Note under neck + waist: "These two unlock body fat % estimation"
- Date picker (same as `_AddEntrySheet` in weight log)
- Validation: at least one measurement must be non-null before Save enables
- Unit toggle (cm / in) pill at the top of the sheet — calls `presenter.setMeasurementUnit()`

**`_MeasurementEntryRow`:**
- Shows: date + waist value (bold, in user's unit) + delta chip (same gold/error color logic as weight)
- Secondary line: lists other logged sites inline, e.g. "Bicep 35 cm · Chest 92 cm"
- Swipe-to-delete or delete icon (match weight log UX)

**`_MeasurementStatsRow` tiles:**
1. Latest waist (formatted in user's unit)
2. Total waist change since first entry
3. Estimated body fat % — shown as `"~18 %"` if computable, `"—"` if not

### Step 6 — Wire into NutritionHistoryScreen
- [ ] Add `_MeasurementSection` widget below `_WeightSection`
- [ ] Shows: latest waist (user's unit) + BF% chip if available + trend direction chip
- [ ] "View all" button → `Navigator.push(MeasurementLogScreen(presenter: presenter))`
- [ ] Empty state: "Log a measurement to track body composition"

### Step 7 — Dashboard recomp integration
- [ ] In `NutritionPresenter.dashboardStatus` (dashboard rehaul spec): when on Cut goal
  and `possibleRecomp` fires, check `waistTrendDirection`:
  - If `waistTrendDirection == down` → upgrade message to
    *"Waist trending down while weight holds — recomp confirmed. Keep going."*
  - If `waistTrendDirection == insufficient` → keep existing message about needing body
    measurements
  - If `waistTrendDirection == stable` or `up` → message stays as "possible recomp — use
    measurements to confirm"

### Step 8 — UX verification
- [ ] Log a waist-only entry — confirm it saves and appears in list
- [ ] Log entry with waist + neck — confirm BF% appears in stats row
- [ ] Toggle cm → in — confirm all display values and input labels update
- [ ] Delete an entry — confirm list updates
- [ ] Log 14+ waist entries decreasing — confirm `waistTrendDirection == down`
- [ ] Trigger recomp XP: cut goal + weight stable + waist down + 7-day cooldown respected
- [ ] Verify `_MeasurementSection` in history screen shows latest waist + BF% when available
- [ ] Verify navigation to `MeasurementLogScreen` and back works without state loss
- [ ] Verify no `AppColors.*` hardcodes in any new or modified widget

---

## RPG Impact

### XP — Confirmed Recomp Milestone

- **Trigger:** `_checkRecompXp()` called inside `logMeasurement()` when all hold:
  1. Active goal is `'cut'`
  2. `waistTrendDirection == down`
  3. `weightTrendDirection == stable`
  4. At least 7 days since `_lastRecompXpDate` (cooldown — prevents weekly farming)
- **Amount:** 300 XP — meaningful but not dominant; consistent with other milestone events
- **Delivery:** `_statsPresenter.addXp(300)` (existing pattern)
- **Storage:** `_lastRecompXpDate` persisted via `saveLastRecompXpDate`
- **Notification:** one-shot local notification — "Recomp confirmed — your body is
  changing even if the scale isn't. +300 XP"

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| User logs entries out of chronological order | Sort `_measurementLog` by `loggedAt` after every add |
| All optional fields null — empty entry saved | `_AddMeasurementSheet` disables Save button unless ≥ 1 field is non-null |
| Waist trend fires with only 1–3 entries | `waistTrendDirection` returns `insufficient` when < 4 waist entries; UI shows "Not enough data" |
| `_TrendPainter` receives `double?` waist values | Filter to `waistCm != null` before passing to chart painter |
| Chart Y-axis range when user mixes kg (weight) and cm (waist) | Each chart only knows its own unit; no cross-axis rendering — no conflict |
| BF% formula returns nonsense for extreme inputs | Clamp result to 3 %–60 % range; return null when waist ≤ neck (math undefined) |
| User switches units mid-session — stored cm values stay valid | Storage always cm; `formatMeasurement` converts for display — switching unit never corrupts data |
| Recomp XP awarded on a maintain or lean gain goal | `_checkRecompXp()` guards on `activeGoal == 'cut'` only |
| XP awarded multiple times in rapid re-logging | 7-day cooldown on `_lastRecompXpDate` prevents it |

---

## Acceptance Criteria

- [ ] `BodyMeasurementEntry` round-trips JSON cleanly with all optional fields null, including `neckCm`
- [ ] `MeasurementUnit` enum exists in `nutrition_goals.dart`; defaults to `metric`
- [ ] `BodyFatCalculator.estimateBodyFatPercent` returns correct value for known male + female inputs; returns null when waist ≤ neck
- [ ] `StorageService` has `keyBodyMeasurements`, `keyMeasurementUnit`, `keyLastRecompXpDate` and all 6 abstract methods implemented
- [ ] `NutritionPresenter` exposes `measurementLog`, `latestMeasurement`, `waistDelta`, `waistTrendDirection`, `estimatedBodyFatPercent`, `measurementUnit`, `formatMeasurement`, `logMeasurement`, `deleteMeasurement`, `setMeasurementUnit`
- [ ] `MeasurementLogScreen` stats row shows latest waist, total change, and BF% (or "—")
- [ ] `_AddMeasurementSheet` Save is disabled until ≥ 1 field is filled
- [ ] Unit toggle pill in sheet switches labels between cm and in; stored value stays cm
- [ ] "Add more" section reveals neck, hips, chest, bicep, thigh fields with note about BF% unlock
- [ ] `_MeasurementSection` appears in `NutritionHistoryScreen` below Weight section; shows BF% chip when computable
- [ ] Confirmed recomp message upgrades when `waistTrendDirection == down` on a Cut goal
- [ ] Recomp XP (300 XP) fires at most once per 7 days; only on Cut goal
- [ ] Recomp XP notification fires alongside XP award
- [ ] No `AppColors.*` tokens hardcoded in any new or modified widget
- [ ] All touch targets ≥ 44 × 44 px
