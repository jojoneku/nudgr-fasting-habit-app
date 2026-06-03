# Plan 032 — Audit: Performance & Persistence

> **Status:** Audit findings + remediation plan.
> **Severity of domain:** 🔴 High — the persistence model rewrites unbounded blobs on every log, so the app gets *slower the longer someone uses it*. This is a tenure-scaling jank cliff.
> **One-sentence summary:** Large structured data (nutrition history, full finance ledger) lives in SharedPreferences and is fully decoded + re-encoded on the UI thread on every single mutation; several views also rebuild entirely on each `notifyListeners()`.

---

## Findings

### 🔴 C1 — Every meal log rewrites the entire, never-pruned nutrition-log blob (synchronous JSON on the platform thread)
- **Where:** `local_storage_service.dart:264-272` (`saveNutritionLog`).
- **Problem:** It reads `keyNutritionLogs`, `jsonDecode`s the **entire map of every day ever logged**, inserts one day, then `jsonEncode`s the whole thing back. The stored map is **never pruned** — `loadNutritionHistory` (`:319`) only *reads* the last 30 but storage keeps everything. After a year that's ~365 day-objects decoded + re-encoded on **every food entry.** It cascades: `addFoodEntry` (`nutrition_presenter.dart:1014-1024`) then runs `_updateLogStreak`, `_checkGoalMet`, `_checkProteinGoalMet`, `_checkOvershoot`, each doing its own `getInstance()` + writes. One food log ≈ 1 full-blob decode + 1 full-blob encode + ~4–6 more pref ops.
- **Fix:** Prune the stored map to N days (mirror the chat cap at `:625`), **or** move daily nutrition logs to sqflite (one row per day, write only the changed row), **or** at minimum key each day under `nutrition_log_<date>` so a save touches only that day.

### 🔴 C2 — Each finance transaction decodes ALL transactions, then re-encodes ALL transactions + ALL accounts
- **Where:** `ledger_presenter.dart:237-249` → `_saveAll` (`:663-668`) → `local_storage_service.dart:692-712` (`saveTransactions`).
- **Problem:** `saveTransactions` calls `loadTransactions()` (full decode) just to diff IDs for the sync queue, then `jsonEncode`s the entire list; `saveAll` also re-encodes all accounts. Same anti-pattern across `saveAccounts/saveBills/saveBudgets/saveReceivables/saveInstallments/saveBudgetedExpenses/saveFinanceCategories` (`:655-991`).
- **Fix:** Track the previous ID set in memory (the presenter already holds `_allTransactions`) and pass added/removed IDs to storage instead of re-loading to diff. Long term, move finance records to sqflite with per-row writes.

### 🟠 H1 — The entire 2435-line NutritionScreen rebuilds on every `notifyListeners()`
- **Where:** `nutrition_screen.dart:32-39` — one top-level `ListenableBuilder` wraps `_WeekStrip`, `_StatSection`, `_ChatFeed`, `_ChatInputBar`.
- **Problem:** The presenter notifies very frequently (parse/estimate fire 2× each; `addFoodEntry` triggers a chain). Each notify rebuilds the week strip, stat section, and chat subtree.
- **Fix:** Push `ListenableBuilder` down to only the subtrees that consume changing state; split notify granularity (or use `Selector`-style narrow listenables) so a streak update doesn't rebuild the input bar. (The chat list already uses `ListView.builder` + `ValueKey(msg.id)` at `:714/730` — keep that.)

### 🟠 H2 — Both light and dark `ThemeData` rebuilt from scratch on every settings notification
- **Where:** `fasting_app.dart:238-251` — `build()` calls `_lightTheme()` and `_darkTheme()` inline in the settings `ListenableBuilder`.
- **Problem:** Both full `FlexThemeData` trees are reconstructed on every rebuild even though only one is active, and they don't actually depend on settings (only the *selection* does).
- **Fix:** Build both `ThemeData` once as `late final` fields in `initState`; switch via `themeMode` only.

### 🟠 H3 — `loadNutritionHistory`/`loadActivityHistory` decode the full blob then discard most of it
- **Where:** `local_storage_service.dart:306-324` and `:477-494` — `jsonDecode` everything, sort, then `.take(30)`/`.take(180)`. Called on every `loadState()` and every post-sync `_reloadAll()` (`home_screen.dart:219-224`).
- **Fix:** Prune at write time, or store per-day keys so only the recent N are decoded.

### 🟠 H4 — `prefs.reload()` on the startup path forces a full synchronous re-read of all prefs
- **Where:** `local_storage_service.dart:132` (`loadState`) and `:182` (`loadQuests`).
- **Problem:** `reload()` discards the in-memory cache and re-parses the entire prefs file — including the large nutrition/finance blobs — twice on the startup critical path plus on each sync.
- **Fix:** Drop `reload()` unless you must observe external/native writes; if needed, call it once at app start, not per-loader.

### 🟡 M1 — `nutrition_history_screen` uses plain `ListView` + `.map()` instead of `.builder`
- **Where:** `nutrition_history_screen.dart:49, 459, 958, 1299`.
- **Fix:** Convert day lists to `ListView.builder` so off-screen day cards (with macro breakdowns) aren't built eagerly.

### 🟡 M2 — `_resolveDbMatches` fans out N parallel FTS5 searches, each able to hit a leading-wildcard full scan
- **Where:** `nutrition_presenter.dart:1327-1328` → `_hybridResolveItem:1346` → `food_db_service.dart:72`, with `LIKE '%dense%'` fallback at `:221` (full scan of ~14k rows, no index can serve a leading wildcard).
- **Fix:** Bound concurrency (resolve items sequentially or in small batches); gate or drop the `%dense%` contains-scan now that FTS5 + fuzzy cover most cases.

### 🟡 M3 — `recentFoods` getter re-scans all slots + full history on every access
- **Where:** `nutrition_presenter.dart:844-874` — recomputes a deduped list (with `FoodTemplate` allocations) every call; if read in a build, re-scans history every frame.
- **Fix:** Memoize; invalidate on log mutation; or compute once when the picker opens.

### 🟡 M4 — `savedTemplates` getter copies + sorts the library on every access
- **Where:** `nutrition_presenter.dart:835-842`. Minor (cap 50) but it's a hot getter.
- **Fix:** Sort once on mutation; cache.

### 🟢 Notes / good patterns
- **L1:** 17.3 MB `assets/food_db.sqlite` copy on first run (`food_db_service.dart:198-211`) reads the whole file into memory before writing — happens post-first-frame so doesn't block paint, but consider streaming on low-RAM devices. Versioned filename (`food_db_v10`) leaves stale `v9`… copies on disk — add cleanup of old `food_db_v*.sqlite` (~17 MB per schema bump).
- **L3:** DB queries themselves are sound — FTS5 + bm25, parameterized `IN (...)` batch lookups (`:185`), paged iteration. No N+1 in the DB layer; the only scan risk is the M2 leading-wildcard LIKE.
- **L4:** Startup is well-structured — `main.dart` only awaits `dotenv.load` + notification init; heavy I/O (DB copy, AI model, sync) is deferred to a post-frame callback.

---

## Remediation order (highest leverage first)
1. **C1 + H3** — prune/repartition the nutrition-log store (kills the unbounded per-log rewrite *and* the load-time full decode). Biggest tenure-scaling win.
2. **C2** — stop re-loading-to-diff in finance saves; track ID deltas in memory.
3. **H1** — narrow the NutritionScreen `ListenableBuilder` scope.
4. **H4** — remove `prefs.reload()` from the startup path.
5. **H2** — cache the two `ThemeData` objects.
6. **M1–M4, L1** — incremental cleanups.

## Definition of done
- Logging a meal touches only that day's bytes (or one DB row), not the whole history; cost is constant regardless of tenure.
- Adding a transaction does not re-decode the full ledger.
- A streak/goal update does not rebuild the week strip or input bar.
- No `prefs.reload()` on the startup hot path; themes built once.
