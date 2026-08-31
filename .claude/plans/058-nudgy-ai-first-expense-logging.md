# Plan 058 — Nudgy AI-First Expense Logging

**Goal:** make Nudgy's expense logging good enough to replace the manual ledger
form. One cloud call over the whole message, every field the form can set,
resolved inline instead of punted to a form.

**Scope:** the expense-logging path only. Bills, goals, set-asides, edit/delete
are explicitly out — see §9.

---

## 1. Why

A message like

> *"Can you add in maribank expenses 175 and 90 for personal shopping. then 115
> for food and drinks avocado ice cream all yesterday."*

produces three wrong entries and a form with only an amount in it. Traced to
three compounding defects:

1. **The regex splits before the AI reads.** `preparseFinanceBatch`
   (`lib/utils/finance_nlp_parser.dart:131`) cuts on `and|then|also|plus|,|;`,
   then drops every piece with no digit in it (`:196`). `"and drinks avocado ice
   cream all yesterday"` has no digit, so the description **and the date** were
   deleted before anything intelligent ran.
2. **The AI is called per fragment, blind to the rest.** `_classifyOnce`
   (`lib/presenters/ledger_presenter.dart:1503`) passes the whole message in as
   `rawText` **and never uses it** — each call sees only its own fragment. The
   model classifying the ice cream received the string `"115 for food"`. It was
   never shown "maribank" or "yesterday".
3. **Nothing is shared across fragments.** Account, category and date stated
   once apply once. `isComplete` requires `accountId`
   (`lib/models/finance/finance_parse_result.dart:173`), so fragments 2 and 3
   failed, deferred, and fell to `_fallbackToForm`.

The fix is not more regex. The model already has the accounts, the categories
and the learned dictionary — it just isn't allowed to see the sentence.

**Design principle: the regex stops deciding. It becomes the offline fallback.**

---

## 2. Target architecture

```
user text
   │
   ├─ AiCoachPresenter.send ─── routes log vs advice
   ▼
LedgerPresenter.sendChatInput(text)
   │
   ├─[A] FinanceEntryExtractor ── ONE cloud call
   │        in : raw message verbatim + today + accounts + categories + dict
   │        out: [ {…}, {…}, {…} ]  ← array, model-named entities
   │
   ├─[B] bindExtractedEntries ── validate + bind names → real IDs
   │        unknown name ⇒ mark that ONE field missing, never kill the row
   │
   ├─[C] AdvisorLogCard ── confirm; missing fields resolved INLINE
   │
   └─[D] commit + learn
```

Four stages become two. Deleted from the happy path: fragment splitting,
per-fragment classification, the `deferred` queue, `_advanceDeferred`, and most
of the clarify loop.

**Fallback:** no network / over the daily cap / malformed response → today's
regex path runs unchanged. `finance_nlp_parser.dart` stays on disk and keeps its
989 lines of tests. It is simply never called first.

---

## 3. The extraction contract

One call. Array out. Every field the manual form can write.

```json
{
  "entries": [
    {
      "type": "outflow",
      "amount": 175,
      "account": "MariBank",
      "transferTo": null,
      "category": "Shopping & Personal",
      "description": "Personal shopping",
      "note": null,
      "date": "2026-08-29",
      "reimbursable": false,
      "expectedReimbursementDate": null,
      "owedBy": null,
      "confidence": 0.93,
      "missing": []
    }
  ],
  "unclear": null
}
```

`missing` is the granularity unlock. Instead of *"one entry needs details"* plus
a blank form, the card says **row 3 has no account** and shows a dropdown.

### Prompt shape (stable prefix first, for cache friendliness)

1. Role + JSON-only instruction
2. Accounts `[{name, kind, liability}]` — active, non-sub, non-custodian
3. Categories `[{name, type}]`
4. Learned token→category dictionary
5. Rules (below)
6. **`today`: ISO date + weekday name** ← makes "yesterday" arithmetic, not regex
7. The user's message, verbatim, last

### Rules the prompt must carry

- Pick `account` / `category` **only** from the supplied lists, matching `name`
  exactly. Never invent. If none fits, leave null and list the field in
  `missing`.
- **Context stated once applies to every entry it plausibly covers.** "in
  maribank … all yesterday" sets the account and the date for the whole list.
  This single rule is what the current pipeline structurally cannot do.
- One entry per distinct amount. Amountless words are **description for the
  nearest entry**, never a dropped fragment.
- `date` is always absolute ISO, resolved against `today`. Never a phrase.
- Never emit a future date unless the message names one explicitly.
- `description` — short Title Case label of *what the money was for*. No amount,
  no account name, no date.
- Category `type` must agree with entry `type`.
- Transfers: `transferTo` required and ≠ `account`.
- `confidence` per entry, 0–1.
- Max 10 entries.
- `unclear` only when the message names no amount at all.

---

## 4. Resolve inline, don't ask

The current clarify loop spends a Bedrock call and a round trip asking *"which
account?"* — a question a dropdown answers instantly and for free, with a
3-turn budget (`kMaxFinanceClarifyTurns`) that ends at the form.

**New rule: structured fields are never asked about, they are picked.**

| Missing field | Resolution |
|---|---|
| account / transferTo | inline dropdown on the row |
| category | inline category picker |
| date | inline date chip |
| type | inline 3-way toggle |
| amount | inline numeric field |

The AI clarify turn survives only for genuinely ambiguous *semantics* (e.g. "was
that a transfer or a payment?"). This is both the efficiency win and the "replace
the manual form" win: the card becomes a compact multi-row form that arrives
pre-filled.

**A row is never dropped and never silently wrong.** Worst case it arrives with
one empty chip.

---

## 5. Efficiency

| Measure | Before | After |
|---|---|---|
| Bedrock calls per message | N (one per fragment) + clarify turns | **1** |
| Clarify round-trips for a missing account | 1 call + 1 user turn | **0** (dropdown) |
| Daily cap (100) headroom | burned 3 on one wrong message | 1 per message |

Additional:
- `max_tokens: 512` (`backend/ai-coach/lambda_function.py:892`) **will truncate**
  an array of three detailed entries into broken JSON. Raise it and make it
  env-configurable, mirroring `_ADVISOR_MAX_TOKENS`.
- `_MAX_PROMPT_LEN = 6000` silently truncates with `prompt[:6000]`. Accounts +
  categories + a growing dictionary can approach this. Trim the dictionary to
  the most-used N client-side, and log when the cap is hit instead of silently
  cutting.
- Stable-prefix-first prompt ordering, so Bedrock prompt caching can be turned
  on later without a rewrite. Not enabling it in this change.

**Latency, stated honestly:** today a fully-resolved regex parse commits with
zero AI calls, instantly. Cloud-first means every log waits ~1–2s. Multi-entry
gets *faster* (1 call, not N); single-entry gets slower. Accepted — the card
shows a thinking state, and correctness was the thing that was broken.

---

## 6. Also fixed here (same complaint, small)

- **"Can you add …?" is routed as advice.** Both `looksLikeExpenseLog`
  (`ai_coach_presenter.dart:934`) and `recognisesLoggableEntry`
  (`ledger_presenter.dart:1170`) veto on `?`. Narrow it: a second-person request
  opener (`can you add|log|record|put|enter|note`) overrides the veto. The rule
  the veto exists for — *"can I afford 4000 food gcash?"* — is first-person
  deliberative and still stays advice.
- **The advisor claims it logged things it cannot log.** `_ADVISOR_SYSTEM_PREFIX`
  (`lambda_function.py:930`) has an anti-hallucination contract for *numbers* and
  nothing about *actions*. Add: you cannot create, edit or delete transactions;
  never state or imply that you have logged something.

---

## 7. Files

**New**
- `lib/utils/finance_entry_extraction.dart` — prompt builder + array response
  parser + entity binding. Pure, unit-testable.
- `lib/models/finance/extracted_entry.dart` — `ExtractedEntry { ParsedTransaction
  txn; Set<EntryField> missing; double confidence; }` + `EntryField` enum.

**Modified**
- `lib/services/ai_coach_service.dart` — add `extractFinanceEntries(...)`
- `lib/services/cloud_ai_coach_service.dart` — implement it
- `lib/services/on_device_ai_coach_service.dart`, `null_ai_coach_service.dart` —
  return null (extraction is cloud-only; on-device stays on the fallback path)
- `lib/presenters/ledger_presenter.dart` — `sendChatInput` cloud-first; retire
  `_startBatch` / `_classifyOnce` / `_deferredSegments` / `_advanceDeferred` from
  the happy path; new chat state carrying entries + missing; inline setters
  (`setEntryAccount`, `setEntryCategory`, `setEntryDate`, …)
- `lib/views/widgets/advisor_log_card.dart` — per-row missing chips + inline
  pickers. **One card serves both surfaces** — web's `web_nudgy_dock.dart` renders
  the same `AiChatSheet`, so mobile and web cannot drift.
- `backend/ai-coach/lambda_function.py` — `max_tokens` env-configurable; advisor
  action guardrail

**Tests**
- `test/utils/finance_entry_extraction_test.dart` — array parse, hallucinated
  account rejected into `missing`, date resolution against an injected `today`,
  context inheritance across entries, type/category agreement, 10-entry cap,
  malformed JSON → null
- `test/presenters/ledger_chat_presenter_test.dart` — cloud path commits; cloud
  failure falls back to regex; inline setters clear `missing`
- `test/views/widgets/advisor_log_card_test.dart` — missing chip renders,
  picking resolves it, "Log all N" enabled only when no row has a missing field
- The regression that started this: the maribank message → 3 entries, all dated
  yesterday, all on MariBank, ice cream described.

---

## 8. Phases

| # | Work | Gate |
|---|---|---|
| 1 | Model + extraction prompt/parser/binding, pure, with tests | tests green |
| 2 | Service method + presenter rewiring + regex fallback | tests green |
| 3 | Card inline resolution | widget tests green |
| 4 | Lambda `max_tokens`, routing `?` fix, advisor guardrail | tests green |
| 5 | `dart format` + full suite + PR to `dev` | CI green |

Branch: `feat/nudgy-ai-first-expense-logging`. One PR, base `dev`.

---

## 9. Out of scope

- Bills, goals, set-asides, receivables — Nudgy still can't create those. That's
  the tool-calling agent, a separate change with its own OpenSpec proposal.
- **Edit and delete.** A chat line names no existing row; still a form trip.
- Custodian and sub-accounts stay excluded from chat (Plan 026 §4).
- On-device extraction. Gemma 0.6B is materially worse at multi-object JSON
  arrays than at single objects; the regex is the better offline fallback.
- Bedrock prompt caching — prompt is ordered for it, enabling it is later.
- Receipt-photo path keeps its current shape; it can feed the new extractor in a
  follow-up.

---

## 10. Risks

| Risk | Mitigation |
|---|---|
| Model returns a name not in the lists | Binding marks that field `missing`; row survives with a picker. Never a fabricated ID. |
| Truncated JSON from `max_tokens` | Raised + configurable; parse failure → regex fallback, never a silent drop |
| Offline / over cap | Regex fallback path, untouched and still tested |
| Latency regression on single entries | Thinking state on the card; accepted trade (§5) |
| Prompt-size cap silently truncating | Dictionary trimmed client-side; cap logged, not silent |
| Two surfaces drifting | Both render the same `AiChatSheet` + `AdvisorLogCard` |
