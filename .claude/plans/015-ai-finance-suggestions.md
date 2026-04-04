# Plan 015 — AI Finance Suggestions
**Status:** DRAFT — Awaiting Approval
**Phase:** 1 of 1
**Depends on:** Plan 013 (Authentication) — user must be signed in to call the proxy
**Depends on:** Plan 014 (Supabase Sync) — MonthlySummary data must be available

---

## Goal

Surface proactive, actionable financial insights using a capable cloud LLM — without
putting an API key in the APK. A Supabase Edge Function acts as a secure proxy between
the app and OpenRouter. The app sends aggregated summary data (never raw transactions).
The user taps "Get Insights" and receives 3–5 plain-language observations with
optional action nudges.

Cost target: **$0** for 2–5 users, **< $1/month** at 50 users (free-tier OpenRouter
model; paid fallback costs fractions of a cent per call).

---

## Architecture

```
App (authenticated)
  │
  │  POST /functions/v1/finance-suggest
  │  Authorization: Bearer <supabase_anon_key>   ← safe: rate-limited per user via RLS
  │  Body: { userId, summaries[], currentMonth }
  │
  ▼
Supabase Edge Function (Deno)
  │  — verifies JWT (auth.uid() == userId)
  │  — rate-limits: max 10 calls/user/day (counter in Postgres)
  │  — builds OpenRouter prompt from summaries
  │
  │  POST https://openrouter.ai/api/v1/chat/completions
  │  Authorization: Bearer <OPENROUTER_API_KEY>   ← stored as Supabase secret, never in APK
  │
  ▼
OpenRouter → free model (deepseek-v3 / llama-3.3-70b)
  │
  └─► structured JSON response → Edge Function → App
```

**Why this is secure:** The OpenRouter key lives exclusively in Supabase's encrypted
secret store. The app only holds the public `supabase_anon_key` (safe to ship in APK).
The Edge Function validates the user JWT before forwarding — unauthenticated callers
are rejected before OpenRouter is ever contacted.

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `supabase/functions/finance-suggest/index.ts` | Create | Edge Function (Deno) |
| `lib/services/suggestions_service.dart` | Create | Service |
| `lib/models/finance/finance_suggestion.dart` | Create | Model |
| `lib/presenters/finance_suggestions_presenter.dart` | Create | Presenter |
| `lib/views/treasury/dashboard/treasury_dashboard_view.dart` | Modify — add insights card | View |
| `lib/views/home_screen.dart` | Modify — wire SuggestionsPresenter | Wiring |

---

## OpenRouter Model Selection

Primary: `deepseek/deepseek-v3-0324:free`
Fallback: `meta-llama/llama-3.3-70b-instruct:free`

Both are free, have 128k context windows, and handle structured JSON output well.
Neither requires payment unless the free tier is exhausted (extremely unlikely at < 50 users).

---

## Prompt Design

The Edge Function sends **aggregated summaries only** — no raw transaction IDs or personal
identifiers other than computed totals. A typical payload is < 800 tokens.

```
System:
You are a personal finance advisor. Analyze the user's last 3 months of financial data
and return ONLY valid JSON — no markdown, no explanation.

{
  "insights": [
    {
      "type": "warning|tip|achievement|alert",
      "title": "Short headline (max 8 words)",
      "body": "1–2 sentence observation with a specific number or % where possible.",
      "action": "Optional short nudge — what to do about it. Null if none."
    }
  ]
}

Rules:
- Return 3–5 insights, most important first.
- Be specific: use actual numbers from the data.
- Do not repeat the same insight twice.
- "warning": spending risk or cashflow shortfall.
- "tip": actionable saving opportunity.
- "achievement": positive trend worth highlighting.
- "alert": upcoming bill risk or overdue item.

User data (PHP):
[JSON of last 3 MonthlySummary objects + current month live totals]
```

---

## Data Payload to Edge Function

Only pre-aggregated fields from `MonthlySummary` are sent — no raw transactions:

```dart
{
  "userId": "uuid",
  "summaries": [
    {
      "month": "2026-02",
      "totalInflow": 51000,
      "totalOutflow": 38200,
      "netSavings": 12800,
      "totalBills": 8500,
      "totalBillsPaid": 8500,
      "billsPaidCount": 4,
      "billCount": 4,
      "totalReceivables": 5000,
      "totalReceived": 5000,
      "categorySpend": { "food": 12000, "transport": 3200, ... }
    },
    // ... 2 more months
  ],
  "currentMonth": { /* live totals from BudgetPresenter + LedgerPresenter */ }
}
```

---

## Rate Limiting (Edge Function)

```sql
-- Supabase migration
CREATE TABLE ai_suggestion_calls (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  call_date DATE NOT NULL DEFAULT CURRENT_DATE,
  call_count INT NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, call_date)
);

ALTER TABLE ai_suggestion_calls ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_rows" ON ai_suggestion_calls USING (user_id = auth.uid());
```

Edge Function logic: `call_count >= 10` → return 429 with `{ error: "Daily limit reached" }`.

---

## Model: `FinanceSuggestion`

```dart
enum SuggestionType { warning, tip, achievement, alert }

class FinanceSuggestion {
  final SuggestionType type;
  final String title;
  final String body;
  final String? action;
}
```

Ephemeral — never persisted. Cleared on next "Get Insights" call.

---

## SuggestionsService Interface

```dart
class SuggestionsService {
  SuggestionsService(SupabaseClient supabase);

  /// Calls the Edge Function proxy. Throws [SuggestionsException] on
  /// network error, auth failure, rate limit, or JSON parse failure.
  Future<List<FinanceSuggestion>> fetchSuggestions({
    required String userId,
    required List<MonthlySummary> summaries,
    required Map<String, dynamic> currentMonth,
  });
}

class SuggestionsException implements Exception {
  final String message;       // user-facing
  final bool isRateLimit;     // true → show "Try again tomorrow"
}
```

---

## FinanceSuggestionsPresenter Interface

```dart
class FinanceSuggestionsPresenter extends ChangeNotifier {
  FinanceSuggestionsPresenter(
    SuggestionsService service,
    TreasuryHistoryPresenter history,
    BudgetPresenter budget,
    LedgerPresenter ledger,
    String userId,
  );

  List<FinanceSuggestion> get suggestions;
  bool get isLoading;
  String? get error;           // null when no error
  bool get isRateLimited;      // true → "Try again tomorrow"
  DateTime? get lastFetchedAt;

  Future<void> fetchSuggestions();
  void dismiss();              // clears suggestions + error
}
```

---

## View: Treasury Dashboard Addition

A collapsible insights card added below the net worth summary in `TreasuryDashboardView`:

```
┌─────────────────────────────────────────────┐
│  AI INSIGHTS                    [Get Insights]│
│─────────────────────────────────────────────│
│  ⚠  Food spending up 28%                    │
│     You spent ₱15,400 on food this month,   │
│     vs ₱12,000 avg over the last 2 months.  │
│     → Review your Food & Drinks budget.     │
│                                             │
│  ✓  Bills fully paid 3 months running       │
│     All 4 recurring bills paid on time.     │
│                                             │
│  💡 Transport budget has ₱1,200 left        │
│     You've used 60% with 10 days remaining. │
└─────────────────────────────────────────────┘
```

- "Get Insights" button → `suggestionsPresenter.fetchSuggestions()`
- `isLoading` → button replaced by spinner
- `isRateLimited` → button disabled, subtitle "Refreshes tomorrow"
- `error` (non-rate-limit) → snackbar
- Icons by type: ⚠ warning, 💡 tip, ✓ achievement, 🔔 alert
- Card hidden entirely if `suggestions.isEmpty && !isLoading`

---

## Implementation Order

1. [ ] Create Supabase migration — `ai_suggestion_calls` rate-limit table
2. [ ] Create `supabase/functions/finance-suggest/index.ts` — JWT validation, rate check, OpenRouter proxy
3. [ ] Set `OPENROUTER_API_KEY` as a Supabase secret (`supabase secrets set`)
4. [ ] Create `FinanceSuggestion` model
5. [ ] Create `SuggestionsService` — HTTP call to Edge Function, JSON parse
6. [ ] Create `FinanceSuggestionsPresenter`
7. [ ] Wire into `AppShell` (requires `userId` from `AuthPresenter`)
8. [ ] Add insights card to `TreasuryDashboardView`
9. [ ] Test: rate limit hit → correct UI state shown
10. [ ] Test: offline → graceful error snackbar, no crash

---

## RPG Impact

None. Insights are advisory — no XP or stat changes triggered by viewing them.

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| OpenRouter free model goes offline / deprecated | `model` is a config constant in the Edge Function — swap without app update |
| JSON parse failure from model | Catch in Edge Function, return `{ error: "parse_failed" }` → app shows generic snackbar |
| User has < 1 month of data | Send what exists; system prompt instructs model to note limited data in insights |
| Supabase free tier Edge Function cold start (~300ms) | Acceptable for a non-real-time feature; show spinner |
| Rate limit table grows unbounded | Nightly Postgres cron: `DELETE FROM ai_suggestion_calls WHERE call_date < CURRENT_DATE - 7` |
| App used offline | `SuggestionsService` catches `SocketException`; presenter sets `error = "No connection"` |
| `supabase_anon_key` in APK | This is by design — it's a public key scoped by RLS. Document clearly. |

---

## Acceptance Criteria

- [ ] "Get Insights" returns 3–5 insights for a user with ≥ 1 month of data
- [ ] OpenRouter API key is not present anywhere in the Flutter source or compiled APK
- [ ] Calling the Edge Function without a valid JWT returns 401
- [ ] Calling more than 10 times in a day returns 429; app shows "Try again tomorrow"
- [ ] Offline → friendly error snackbar, no crash
- [ ] Model returns malformed JSON → Edge Function catches it, app shows generic error
- [ ] Insights card is hidden when no suggestions are loaded
- [ ] All touch targets ≥ 44×44px
- [ ] No logic in `build()` — all state via presenter getters

---

*Implementation order: Plan 013 (Auth) → Plan 014 (Sync) → Plan 015 (AI Suggestions).*
*Present this plan for approval before writing any code.*
