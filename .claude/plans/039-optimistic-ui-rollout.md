# Plan 039 — Optimistic UI Rollout

**Status:** Finance/Treasury done (this PR). App-wide rollout = light backlog below.

## 🎯 Problem

Every mutating action (log / update / delete) felt laggy (~500ms–1s) with no feedback. Root cause is **not** cloud sync (that's debounced 3s via a `Timer`, non-blocking). It's that presenters `await` persistence **before** calling `notifyListeners()`/`safeNotify()`:

```dart
_state = ...mutate...;     // in-memory (instant)
await _storage.saveX();    // jsonEncode(full list) + SharedPreferences write — blocks here
notifyListeners();         // UI only repaints after the write
```

`jsonEncode` of a large list is synchronous CPU work on the main isolate, and the legacy prefs plugin rewrites the whole blob — so the cost grows with the data and lands before the repaint.

## ✅ Fix (the pattern)

Notify **immediately** after the in-memory mutation, then persist:

```dart
_state = ...mutate...;
notifyListeners();         // repaint instantly
await _storage.saveX();    // encode + write after the frame is scheduled
```

Because `saveX` hits an `await` (e.g. `SharedPreferences.getInstance()`) before the heavy encode, the event loop paints the new state first. Local-first, so the failure risk (a write failing after the UI already updated) is negligible; add revert-on-error only if a specific path warrants it.

**Rule of thumb:** in a `ChangeNotifier` mutation, the order is *mutate → notify → persist*, never *mutate → persist → notify*. Keep dependent-presenter refreshes (e.g. `_notifyDependents()` that reload from storage) **after** the await.

## ✅ Done — Finance / Treasury (this PR)

- `LedgerPresenter` — add/update/delete transaction, transfer, save account, add/delete category, chat commit (via addTransaction)
- `BudgetPresenter` — setBudget, removeBudget, addCategory
- `BillsReceivablesPresenter` — bill/receivable/budgeted-expense CRUD + mark-paid/received
- `InstallmentPresenter` — add/update/delete
- `TreasuryDashboardPresenter` — account add/update/delete
- `GroceryCartPresenter` — already shipped optimistic (PR #201)

## 📋 App-wide rollout (backlog — own PR(s))

Apply the same *mutate → notify → persist* reorder to the remaining presenters' mutation methods:

- [ ] `NutritionPresenter` — log/edit/delete food, set goals (highest-traffic after finance)
- [ ] `ActivityPresenter` — log activity, set goals
- [ ] `QuestPresenter` — complete/add/edit quest, routines
- [ ] `FastingPresenter` — start/stop/edit fast, goal changes
- [ ] Weight / body-measurement mutations
- [ ] `SettingsPresenter` — toggles (likely already cheap)

### Guidance for the rollout
- Only reorder methods that **await a save before notifying**. Pure setters that already notify synchronously need no change.
- Watch methods that interleave **XP awards** or **dependent reloads** between save and notify — move only the user-facing `notify` up; leave XP/dependent calls after the await.
- No new tests are usually required (existing tests await the full method, so final state is unchanged), but add a test if a method gains revert-on-error.

## ⚠️ Deeper option (not now)
If large-list `jsonEncode` still janks the main isolate on big datasets, move encoding off-thread (`compute`) or migrate hot collections off the monolithic prefs blob. Optimistic notify is the cheap 90% win; revisit only if profiling shows residual jank.
