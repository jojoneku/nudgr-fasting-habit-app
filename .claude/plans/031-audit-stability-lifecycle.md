# Plan 031 — Audit: Stability, State Lifecycle & Crash Safety

> **Status:** Audit findings + remediation plan.
> **Severity of domain:** 🔴 High — the highest-probability crashes in the app, triggered by the most common interactions (closing a sheet while the AI is thinking).
> **One-sentence summary:** Presenters fire `notifyListeners()` after `await` without disposed-guards, so dismissing a screen mid-async throws "A ChangeNotifier was used after being disposed"; the AI chat presenter has no `dispose()` at all and streams tokens into a dead notifier.

---

## Findings

### 🔴 C1 — Systemic missing disposed-guards on async `notifyListeners()`
- **Where (notify calls / guarded sites):**
  - `nutrition_presenter.dart`: ~47 notify, only 1 guarded (`:2991`). Post-await examples: `estimateMeal` (`:1231`), `parseMeal` (`:1271`), `_tryCloudParseFood` notifies after a 25s cloud call (`:2053-2055`).
  - `ledger_presenter.dart`: 26 notify, 0 guards.
  - `ai_coach_presenter.dart`: 13, 0. `activity_presenter.dart`: 14, 0. `bills_receivables_presenter.dart`: 14, 0. `installment_presenter.dart`: 8, 0. `stats_presenter.dart`: 9, 0.
- **Problem:** If the listening view is dismissed mid-`await` (very likely on a 25–30s AI call), `ChangeNotifier.notifyListeners()` throws on a disposed notifier.
- **Impact:** Crash on the single most common AI interaction — closing the meal sheet while parsing.
- **Fix:** Add a `_disposed` flag set in `dispose()` plus a `_safeNotify()` helper, and route **every** post-await mutation through it. `NutritionPresenter` already has the flag (`:311,342`) but uses it in 1 of ~47 sites — finish the job everywhere.

### 🔴 C2 — `AiCoachPresenter` has no `dispose()` and streams tokens unguarded
- **Where:** `lib/presenters/ai_coach_presenter.dart:16` (no `dispose()` override), `:92-110` (`await for (final token in _service.respond(...)) { …; notifyListeners(); }`).
- **Problem:** When the chat sheet closes mid-stream, the in-flight `await for` keeps firing `notifyListeners()` on a disposed notifier; there's no `StreamSubscription` to cancel.
- **Impact:** Guaranteed crash + leaked stream work on every interrupted AI chat.
- **Fix:** Hold the subscription, override `dispose()` to set a disposed flag and cancel/break the stream, and guard the per-token notify.

### 🟠 H1 — Unhandled async chain in sync bootstrap
- **Where:** `home_screen.dart:187-207` (`_initSync` awaits `pullAll()` → `pushPending()` → `pushAll()` with no try/catch), invoked from a post-frame callback and the `onFirstSignIn` callback. `sync_service.dart:355-357` deliberately `rethrow`s on pull failure.
- **Problem:** A network hiccup at sign-in becomes an unhandled exception in an async callback — no UI, no retry. Worse, the `_syncService != null` early-return (`:188`) blocks retry after a partial failure.
- **Fix:** Wrap in try/catch, surface a retry affordance, keep the service recoverable after a failed init.

### 🟡 M1 — Silently swallowed deserialization → undiagnosable data loss
- **Where:** `local_storage_service.dart:151` (`catch (_) {}` around `FastingLog.fromJson`), `sync_queue.dart:34,43`.
- **Problem:** One corrupt history blob silently drops the user's entire fasting history with zero log output. Sync-queue parse errors vanish the same way.
- **Fix:** At least `debugPrint` the error (siblings at `:84-85` already do), and preserve the raw blob for recovery rather than discarding it.

### 🟢 L1 — Notification init failure swallowed at startup
- **Where:** `main.dart:12-16` — catches and only `debugPrint`s; app proceeds.
- **Fix:** Acceptable not to block startup, but set a flag surfaced in Settings so a permanent permission/init failure isn't invisible for a notification-centric app.

### 🟢 Good patterns to keep
- `HubPresenter` pairs `addListener`/`removeListener` in `dispose()` (`hub_presenter.dart:26-28, 104-106`).
- `FastingPresenter` cancels its `Timer? _ticker` (`fasting_presenter.dart:21, 145`) and has guards.
- These are the template the other presenters should copy.

---

## Remediation order
1. **C2** — fix `AiCoachPresenter` lifecycle (smallest, highest-certainty crash).
2. **C1** — roll out `_disposed` + `_safeNotify()` to every presenter; prioritize nutrition, ledger, ai_coach, activity, bills.
3. **H1** — make `_initSync` try/caught, retryable, and recoverable.
4. **M1** — log + preserve corrupt blobs instead of silent-dropping.
5. **L1** — surface notification-init failure in Settings.

## Suggested shared helper
```dart
mixin SafeNotifier on ChangeNotifier {
  bool _disposed = false;
  @override
  void dispose() { _disposed = true; super.dispose(); }
  void safeNotify() { if (!_disposed) notifyListeners(); }
}
```
Apply across presenters; replace post-await `notifyListeners()` with `safeNotify()`.

## Definition of done
- Dismissing any sheet/screen mid-AI-call or mid-sync never throws a disposed-notifier error.
- `AiCoachPresenter` cancels its stream on dispose.
- Sync bootstrap failures are caught, surfaced, and retryable.
- Corrupt persisted blobs are logged (and ideally recoverable), never silently dropped.
