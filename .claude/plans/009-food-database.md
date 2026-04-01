# Feature Plan: Local Food Database — Alchemy Lab DB Layer

> Status: DRAFT
> Created: 2026-03-22
> Depends on: Plan 007 (Calorie Counting v2) — `FoodDbService` stub must exist before this plan executes
> Blocks: Plan 007 step 5 (FoodDbService real implementation)

---

## Goal

Ship a bundled SQLite food database that lets users search food by name, enter grams, and have calories (and macros) auto-calculated — fully offline, no API calls.

---

## Data Source Options

| Source | Size (raw) | License | Quality | Notes |
|---|---|---|---|---|
| USDA FoodData Central (SR Legacy) | ~40MB raw, ~5MB filtered SQLite | Public domain | High — lab-tested values | Best accuracy; covers common foods well |
| Open Food Facts | ~3GB raw, ~15MB filtered SQLite | ODbL (open) | Variable — user-contributed | Huge catalog; noisy; barcodes available |
| Nutritionix (API only) | — | Commercial | High | Not offline-viable |
| **Recommendation** | **USDA SR Legacy** | **Public domain** | ✓ | Simpler schema, better accuracy for common foods |

**Decision:** USDA FoodData Central — SR Legacy subset. Filter to ~2,000 most common foods (staples, proteins, produce, grains, dairy, fast food) to keep the asset under 3MB.

---

## Database Schema

```sql
-- Primary food table
CREATE TABLE foods (
  id        TEXT PRIMARY KEY,    -- USDA FDC ID as string
  name      TEXT NOT NULL,       -- Display name, Title Case
  category  TEXT,                -- e.g. "Poultry", "Vegetables", "Grains"
  cal       REAL NOT NULL,       -- kcal per 100g
  protein   REAL,                -- g per 100g
  carbs     REAL,                -- g per 100g
  fat       REAL                 -- g per 100g
);

-- FTS5 virtual table for fast prefix search
CREATE VIRTUAL TABLE foods_fts USING fts5(
  name,
  content='foods',
  content_rowid='rowid'
);

-- Trigger to keep FTS in sync
CREATE TRIGGER foods_ai AFTER INSERT ON foods BEGIN
  INSERT INTO foods_fts(rowid, name) VALUES (new.rowid, new.name);
END;
```

---

## FoodDbService — Real Implementation

```dart
class FoodDbService {
  Database? _db;

  Future<void> init() async {
    // Copy bundled asset to app documents dir (only on first run / version bump)
    final dbPath = await _resolveDbPath();
    _db = await openDatabase(dbPath, readOnly: true);
  }

  Future<String> _resolveDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/food_db_v1.sqlite';
    if (!File(path).existsSync()) {
      final data = await rootBundle.load('assets/food_db.sqlite');
      await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return path;
  }

  Future<List<FoodDbEntry>> search(String query) async {
    if (_db == null || query.trim().isEmpty) return [];
    final q = '${query.trim().toLowerCase()}*';  // prefix match
    final rows = await _db!.rawQuery(
      'SELECT f.* FROM foods f '
      'JOIN foods_fts ON foods_fts.rowid = f.rowid '
      'WHERE foods_fts MATCH ? LIMIT 20',
      [q],
    );
    return rows.map(FoodDbEntry.fromRow).toList();
  }

  Future<FoodDbEntry?> getById(String id) async {
    if (_db == null) return null;
    final rows = await _db!.query('foods', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : FoodDbEntry.fromRow(rows.first);
  }

  Future<void> close() async => _db?.close();
}
```

---

## Data Pipeline (One-Time Setup)

```
USDA FoodData Central
  ↓ Download "SR Legacy" JSON (~40MB)
  ↓ Python script: filter_usda.py
      - Keep foods with complete cal/protein/carbs/fat values
      - Filter to ~2,000 common foods by frequency/category
      - Normalize names to Title Case
      - Output: foods.csv
  ↓ sqlite3 CLI: import foods.csv → foods table
  ↓ sqlite3: CREATE VIRTUAL TABLE foods_fts ...
  ↓ sqlite3: VACUUM (reduce file size)
  ↓ Output: assets/food_db.sqlite (~2–3MB)
```

Script lives at: `scripts/build_food_db.py`

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/services/food_db_service.dart` | Implement (replace stub) | Service |
| `assets/food_db.sqlite` | Add generated asset | Asset |
| `pubspec.yaml` | Add `sqflite`, `path_provider`; register asset | Config |
| `scripts/build_food_db.py` | Create data pipeline script | Tooling |
| `scripts/README_food_db.md` | Document how to regenerate DB | Docs |

---

## Implementation Steps

1. [ ] Add `sqflite: ^2.3.0` and `path_provider: ^2.1.2` to `pubspec.yaml`
2. [ ] Write `scripts/build_food_db.py` — USDA SR Legacy → filtered SQLite
3. [ ] Run pipeline → generate `assets/food_db.sqlite`
4. [ ] Register `assets/food_db.sqlite` in `pubspec.yaml`
5. [ ] Implement `FoodDbService.init()` with asset-copy-to-documents logic
6. [ ] Implement `FoodDbService.search()` with FTS5 `MATCH`
7. [ ] Implement `FoodDbService.getById()`
8. [ ] Wire `FoodDbService.init()` into `AppShell.initState()` (alongside other service inits)
9. [ ] Verify: search "chicken" returns ≥5 results with complete macro data
10. [ ] Verify: asset copy only happens once (subsequent launches skip)
11. [ ] Verify: graceful empty results when query matches nothing

---

## Risks

| Risk | Mitigation |
|---|---|
| Asset copy blocks UI on first launch | Run copy in `FoodDbService.init()` before app renders (or show loading screen) |
| SQLite asset too large (>5MB) | Filter more aggressively — cap at 1,500 foods if needed |
| USDA names are verbose ("Chicken, broilers or fryers, breast...") | Normalize in Python script — strip parenthetical qualifiers, Title Case |
| FTS5 not available on all Android/iOS SQLite builds | Fall back to `LIKE '%query%'` — slower but always works |
| DB version mismatch after app update | Version the file name (`food_db_v1.sqlite`) — bump on schema changes |

---

## Acceptance Criteria

- [ ] Searching "white rice" returns "White Rice, Cooked" with correct cal/macro values
- [ ] Entering 150g → calories auto-populate correctly (cal = `caloriesPer100g * grams / 100`)
- [ ] Search results appear in < 200ms on mid-range device
- [ ] First-launch asset copy completes before user reaches NutritionScreen
- [ ] Empty results handled gracefully (no errors, "No results — try manual entry" state)
- [ ] Asset is < 5MB
- [ ] Works fully offline
