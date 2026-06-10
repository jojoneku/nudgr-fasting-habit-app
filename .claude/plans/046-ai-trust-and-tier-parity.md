# Plan 046 — AI Trust, Tier Parity & Data-Aware Coach

> Status: PLANNED — NOT IMPLEMENTED · Authored: June 10, 2026
> No separate spec — see **Spec Addendum** below for the `docs/ai_coach_spec.md` amendments.
> Context: Plan 033 (food-AI audit, H2/H3 + SEV-3 trust items), Plan 034 (backend audit), Plan 027 (badge groundwork, shipped).

## Conflict Check

| Check | Finding |
|---|---|
| **File overlap** | Plan 041 backlog reorders `NutritionPresenter` mutations (notify-before-persist); Part A touches commit paths in the same file — land 041's nutrition reorder first or rebase carefully. |
| **Model overlap** | None new. `FoodEntry.confidence` + `EstimationSource` already exist (Plan 027/034); Part A adds a *derived* band getter only. |
| **Presenter split** | `AiCoachPresenter` owns chat; `NutritionPresenter` owns food resolution. This plan respects that split. |
| **XP routing** | None. |
| **HubScreen** | Not touched. |
| **Supersedes** | Plan 027 **Wave 2.2** (first-run AI prompt) stays open and separate. This plan completes 034's remediation item 4 ("decide chat's tier story") and 033's H2-adjacent UI trust work. |
| **Dependency order** | Backend auth + rate limit (034 SEV-1) — **already shipped and verified** (see findings). Nothing else blocks. |

## Goal

Three gaps, one theme: **the coach knows less than the app does, and the app
tells the user less than it knows.** (a) Fabricated/low-confidence macro
estimates commit looking nearly identical to verified DB hits — no graded band,
no tap-to-correct, no confirm nudge on the worst tier. (b) The "Cloud AI Coach"
toggle controls **food parsing only**: chat always runs on-device (or canned)
even though the cloud `respond` path is built end-to-end and the user opted in.
(c) Chat context is a thin today-only snapshot — the coach can't answer "how
was my week?", "what did I spend on food this month?", or "is my weight
trending down?" even though every presenter already computes those answers.
Fix all three without adding friction — logging never blocks, chat silently
falls back, context stays scoped and bounded.

## Key findings (verified June 10, 2026 — read before assuming greenfield)

**Part (a) is further along than the audits imply:**
- `FoodEntry` already persists `confidence` (0–1) **and** `estimationSource`
  (`food_entry.dart:13-14`), plus `needsConfirmation` (= confidence < 0.6, `:36`).
- `EstimationSource` (`lib/models/estimation_source.dart`) already has the full
  badge system (`showBadge`, labels `DB`/`You`/`Cloud`/`Cloud~`/`Photo`/`~`/`Set`,
  theme-aware `badgeColor`, `isTrusted`). The ~2 kcal/g fallback **is already
  propagated** as `cloudAiFallback` ("Cloud~", error color) — 034 SEV-3 partially shipped.
- The chat feed already renders a source badge + a "?" low-confidence badge
  (`nutrition_screen.dart:1577-1594`) — but both are `Tooltip`-wrapped static
  chips: **no tap action, no correction route, binary not banded.**
- `LogMealSheet` (legacy) still tags everything `keywordDensity`
  (`log_meal_sheet.dart:1005`) — Plan 033 Phase 0 retires it; no badge polish there.

**Part (b) — cloud chat is ~90 % built, 0 % wired:**
- Composition root is **`lib/views/home_screen.dart` (not main.dart)**:
  `CloudAiCoachService` constructed at `:102`, gated by
  `settingsPresenter.useCloudAi` via `_cloudAi.enabled` (`:105`, listener `:221`),
  injected into `NutritionPresenter` only. `AiCoachPresenter` gets
  `service: _onDeviceAi` (`:138-143`) and imports only Null/OnDevice.
- `AiCoachPresenter.setTier()` flips a display field and notifies — never swaps
  the service (`ai_coach_presenter.dart:156-160`).
- `CloudAiCoachService.respond` is fully implemented (`:118-145`, single-chunk
  yield, not streaming) and the Lambda `respond` op has **JWT auth + server-side
  `DAILY_CAP=100`** Supabase-RPC rate limiting
  (`backend/ai-coach/lambda_function.py:13, 99-104`) — 034 SEV-1 is closed.
- Still open from 034 SEV-3: no user/assistant alternation enforcement →
  Bedrock ValidationException risk on the respond path.
- Settings copy (`settings_screen.dart:285-289`): title "Cloud AI Coach", subtitle
  "primary food parser when signed in" — honest about parsing, misleading title.

**Part (c) — context plumbing exists but is today-only, and finance is dead:**
- `AiCoachContext` (`lib/models/ai_coach_context.dart`) carries today's
  calories/macros, live fast state, streak, level/XP/HP — and `monthBudget` /
  `monthSpent` fields (`:27-28`) that `_buildContext()`
  (`ai_coach_presenter.dart:195-215`) **never populates**: even the treasury
  entry point chats with zero finance data.
- `toPromptSummary()` (`:49-80`) is the single injection point into the system
  prompt — both tiers consume it, so enrichment lands on cloud *and* on-device
  for free.
- No history of any kind is sent: no past days, no weight entries, no
  transactions, no quest record. The presenters already compute the aggregates
  (`sevenDayAvgCalories`, `proteinHitRate7d`, weight trend, budget actuals,
  upcoming bills) — nothing new to calculate, only to wire.

## Part A — Confidence bands on food entries

**Band (derived, not persisted — confidence + source already are):**

```dart
// lib/models/food_entry.dart
enum ConfidenceBand { high, medium, low }

ConfidenceBand get confidenceBand {
  if (!estimationSource.isTrusted) {
    return (confidence ?? 0) < 0.6 ? ConfidenceBand.low : ConfidenceBand.medium;
  }
  return (confidence ?? 1.0) >= 0.8
      ? ConfidenceBand.high
      : (confidence ?? 1.0) >= 0.6 ? ConfidenceBand.medium : ConfidenceBand.low;
}
```

`cloudAiFallback` + `keywordDensity` are always `low` regardless of confidence
(the number is fabricated alongside the macros).

**UI (chat feed `_FoodItemDisplay` + anywhere `FoodEntry` tiles render):**
- `high` — no change (DB stays silent, per `showBadge`).
- `medium` — existing source badge becomes a **tappable** "~ estimated" `AppBadge`
  (`lib/views/widgets/system/indicators/app_badge.dart`); tap → existing manual
  edit sheet, pre-filled.
- `low` — entry commits normally (**never block logging**) but renders an
  error-tinted "~ estimated — tap to verify" chip that persists until the user
  edits or taps "Looks right" (one-tap confirm → confidence bumped to 0.8 via
  copyWith). "Forced-confirm" = forced to *see*, never forced to *act*.
- Only confirmed/edited entries may auto-learn (keeps Plan 027's guardrail;
  closes 033 H2 fully).

## Part B — Honor the Cloud toggle for chat

```dart
// AiCoachPresenter — constructor injection only (rule 6)
AiCoachPresenter({
  required StatsPresenter stats,
  required FastingPresenter fasting,
  NutritionPresenter? nutrition,
  AiCoachService? onDevice,
  AiCoachService? cloud,        // NEW — CloudAiCoachService from home_screen
});

AiCoachService get _chatService =>
    (_cloud != null && _cloud.isAvailable) ? _cloud : _onDeviceOrNull;
AiCoachTier get activeTier => _chatService.tier;   // replaces the dead setTier field
```

- **Selection per send():** cloud when `isAvailable` (endpoint + toggle + signed
  in — existing logic in `CloudAiCoachService.isAvailable`); else on-device; else
  Null. Offline/unauthenticated → silent on-device fallback with the tier badge
  crossfade the spec already designed.
- **Alternation fix (034 SEV-3):** in `CloudAiCoachService.respond`, coalesce
  consecutive same-role messages and drop a leading assistant turn before POST.
- **Client-side soft cap:** `StorageService` key `aiChat.cloudTurnCount.<yyyy-MM-dd>`
  (int, user-scoped via `_k()`); after **30 cloud turns/day** route to on-device
  with a one-line notice. The server cap (100/day, shared with food parsing) stays
  the hard wall; the soft cap keeps chat from starving food parsing.
- **Honest settings copy:** subtitle → "Claude Haiku via AWS Bedrock — powers food
  parsing and coach chat when signed in. Falls back to on-device offline."
- **429 handling:** on-device fallback + notice (mirror the
  `PhotoParseStatus.rateLimited` pattern).

## Part C — Data-aware coach context

**Principle: entry-point-scoped, aggregates-only, bounded.** Each chat entry
point gets the summaries relevant to it — never the whole vault, never raw
records.

| Entry point | Adds to the base Player Status block |
|---|---|
| `general` | Nothing extra (today snapshot as now) |
| `nutrition` | 7-day avg calories vs goal, protein hit rate (7d), latest weight + 14-day trend direction, goal weight if set (Plan 045) |
| `fasting` | Last 7 fasts: completed count, avg duration, longest; current protocol name |
| `treasury` | Month budget vs spent (wire the dead fields), top 3 spend categories this month (name + ₱ amount), bills due in next 7 days (name + amount + due day), liquid cash total |
| `stats` | Quests completed today / this week, streak freeze state, XP to next level |

**Model:** extend `AiCoachContext` with nullable section objects rather than 20
flat fields — `NutritionWeekSummary?`, `FastingWeekSummary?`,
`TreasuryMonthSummary?`, `QuestSummary?` — each an immutable value object with
its own `toPromptLines()`. `toPromptSummary()` concatenates base + whichever
section is non-null. Populate only the section matching `entryPoint` (plus the
base block).

**Wiring:** `AiCoachPresenter` constructor gains optional
`BudgetPresenter? budget`, `TreasuryDashboardPresenter? treasury`,
`BillsReceivablesPresenter? bills`, `QuestPresenter? quests` (constructor
injection only, rule 6; all nullable so existing tests stand).
`_buildContext()` assembles the section from presenter getters — **no math in
the presenter beyond delegation**; if an aggregate doesn't exist yet, it goes
on the owning presenter, not here.

**Privacy rules (hard, documented in spec):**
- Aggregates only — never raw transaction descriptions, notes, or
  per-transaction rows; never individual food-entry timestamps; never account
  numbers. Category names and bill names are allowed (user-authored labels).
- Context is rebuilt per `send()` and injected into the system prompt only —
  nothing persisted server-side beyond the Lambda's existing request logging.
- The enriched context ships to AWS Bedrock **only when the cloud tier
  answers**; on-device gets the same summary locally.
- Size cap: `toPromptSummary()` clamped to ~600 tokens (~2,400 chars) — section
  builders truncate lists (top 3 categories, max 5 bills) so a power user's
  data can't blow up the prompt.

**UX:** a one-time disclosure line in the chat sheet the first time an
enriched entry point is opened with Cloud AI on: "Summaries of your
{nutrition/finance} data are shared with the cloud coach. Aggregates only."
Dismiss persists via StorageService (user-scoped key).

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/models/food_entry.dart` | Modify (band getter, confirm copyWith) | Model |
| `lib/views/nutrition/nutrition_screen.dart` | Modify (tappable badges, verify chip) | View |
| `lib/presenters/nutrition_presenter.dart` | Modify (confirmEntry, learn-on-confirm) | Presenter |
| `lib/presenters/ai_coach_presenter.dart` | Modify (dual-service selection) | Presenter |
| `lib/services/cloud_ai_coach_service.dart` | Modify (alternation coalesce) | Service |
| `lib/services/storage_service.dart` (+ local impl) | Modify (cloud-turn key) | Service |
| `lib/views/home_screen.dart` | Modify (inject `cloud:` + treasury/quest presenters into AiCoachPresenter) | Root |
| `lib/views/settings_screen.dart` | Modify (copy) | View |
| `lib/models/ai_coach_context.dart` | Modify (section value objects, scoped `toPromptSummary`, size clamp) | Model |
| `lib/views/widgets/ai_chat_sheet.dart` | Modify (one-time data disclosure line) | View |
| `test/presenters/ai_coach_presenter_test.dart` | Create | Test |
| `test/models/food_entry_test.dart` | Extend (band boundaries) | Test |
| `test/models/ai_coach_context_test.dart` | Create (section scoping, truncation, clamp) | Test |

## Implementation Order

1. [ ] **A1 — Model:** `ConfidenceBand` getter + boundary tests (0.59/0.6/0.79/0.8,
       fallback sources pinned low).
2. [ ] **A2 — Presenter:** `confirmEntry(id)` (mutate → notify → persist, per
       Plan 041 pattern); gate auto-learn of open estimates behind confirm/edit.
3. [ ] **A3 — View:** tappable badge → edit sheet; low-band verify chip with
       "Looks right" one-tap. Audit every `FoodEntry` render site (chat feed,
       recent-days expansion in history screen) for band coverage.
4. [ ] **B1 — Service:** alternation coalesce in `respond`; map 429 → typed result.
5. [ ] **B2 — Presenter:** dual injection, per-send selection, soft-cap counter,
       remove dead `setTier` mutation (keep getter), fallback notice message.
6. [ ] **B3 — Root + Settings:** pass `cloud: _cloudAi` in `home_screen.dart`;
       update toggle copy.
7. [ ] **C1 — Model:** section value objects + scoped `toPromptSummary()` +
       truncation/clamp, with unit tests (each entry point yields only its
       section; treasury list caps respected).
8. [ ] **C2 — Presenter + Root:** new optional presenter deps, `_buildContext()`
       populates the matching section (incl. wiring the dead
       `monthBudget`/`monthSpent`); inject in `home_screen.dart`.
9. [ ] **C3 — View:** one-time disclosure line in `ai_chat_sheet.dart`,
       dismissed flag via StorageService.
10. [ ] **Tests:** mockito (per `test/mocks.dart` conventions) — Given cloud
       available When send Then cloud used; Given offline/signed-out Then on-device;
       Given soft cap hit Then fallback + notice; alternation coalescing; Given
       treasury entry point Then context has finance section and no nutrition
       history.
11. [ ] **Verify:** `flutter analyze` + `dart format`; manual pass: toggle off/on
       mid-session, airplane mode, signed-out; ask "how was my week?" from each
       entry point and confirm grounded answers.

## RPG Impact

None — no XP, streak, or notification changes. Trust UI is cosmetic + data-quality.

## Risks

- **Badge noise:** medium band reuses the existing badge slot — net new chrome
  only on low band. Watch crowding in the chat row (already 3–4 badges).
- **Cloud chat cost:** server cap (100/day) + client soft cap (30) + JWT auth
  bound it; Haiku turns ≈ $0.001 — negligible, and capped.
- **Cloud respond is non-streaming** — long answers appear at once after ~2–5 s.
  Acceptable v1 (typing indicator exists); SSE is a separate backend task.
- **Plan 041 collision** in `nutrition_presenter.dart` — sequence after the
  nutrition optimistic-UI PR.
- **Context bloat / prompt drift:** every added section is more tokens per turn
  and more surface for the small on-device model to get confused by — the
  per-entry-point scoping and 600-token clamp are the guardrails; resist
  "send everything always."
- **Privacy expectation:** users may not expect finance summaries to leave the
  device — the disclosure line + aggregates-only rule are the mitigation; spec
  documents exactly what is and isn't sent.
- **Plan 045 dependency (soft):** weight trend + goal weight lines get richer
  once 045 lands; C ships fine without it (omit lines whose getters don't exist
  yet).

## Acceptance Criteria

- [ ] Low-band entries always show the verify chip; logging is never blocked
- [ ] One-tap "Looks right" promotes confidence and (only then) allows auto-learn
- [ ] Fabricated estimates (`cloudAiFallback`, `keywordDensity`) can never render
      as high confidence regardless of stored confidence value
- [ ] With Cloud AI on + signed in, chat `send()` hits the Lambda; toggle off or
      offline → on-device, no error surfaced, tier badge updates
- [ ] 30-turn soft cap falls back with notice; 429 handled gracefully
- [ ] Settings copy mentions both parsing and chat
- [ ] Treasury chat can answer "what did I spend this month / what's due soon?"
      from injected aggregates; nutrition chat can answer "how was my week?"
- [ ] No raw transaction descriptions, notes, or per-record rows ever appear in
      `toPromptSummary()` output (asserted in tests)
- [ ] Context stays ≤ ~600 tokens regardless of data volume (clamp tested)
- [ ] One-time disclosure shown before first enriched cloud chat per user
- [ ] `flutter analyze` + `dart format` clean; new presenter/model tests green

---

## Spec Addendum — amendments to `docs/ai_coach_spec.md`

Amends (does not rewrite) these spec sections:

1. **Presenter API** — `setTier()` drops as a user-driven mutation; tier is
   *derived* per message (`activeTier` = service actually used). Constructor
   gains injected `onDevice`/`cloud` services.
2. **AWS Backend** — section is stale (Node 20 / x-api-key / SSE): deployed
   reality is Python 3.12, Supabase-JWT auth, `DAILY_CAP=100` Supabase-RPC rate
   limit, single-shot JSON response (no streaming).
3. **Storage** — `aiCoachTier`/`aiCoachCloudOptIn` keys were never built; the
   real toggle is `kUseCloudAi`. Add `aiChat.cloudTurnCount.<date>` (soft cap).
4. **Edge Cases** — "Offline + cloud tier → fall back on-device with badge"
   becomes implemented behavior for chat, not just food parsing.
5. **Acceptance Criteria** — "Cloud tier requires explicit opt-in" now genuinely
   covers chat; "Lambda returns streamed SSE" downgraded to single-response
   until a streaming backend ships.
6. **Context Injection** — `AiCoachContext` section grows from today-snapshot to
   entry-point-scoped summaries (nutrition week / fasting week / treasury month
   / quest record) with the aggregates-only privacy rule, ~600-token clamp, and
   first-use disclosure documented as normative behavior.
