# Plan 066 — Nudgy: the snapshot is an index, the tools are the record

**Status:** revision 2 (2026-10-30). Phases 1 and 2 built (section 10); phase 3 next. Revision 2 is the
result of a critical review of revision 1: section 9 lists what changed and why.

**Trigger.** On 2026-10-30 at about 6:42 PM Manila, the user asked Nudgy about
the deferral on 2 installment plans (Xiaomi, Panasonic Refrigerator). Nudgy said
that it could not see a deferral. The user asked again ("eh? you can't see in
the installment that it is deferred?"). Nudgy answered from the snapshot again.
The deferral was available: `find (entity installment)` returns
`first payment month` and `deferred: N months`
([finance_finder.dart:424-426](../../lib/presenters/finance_finder.dart)).

**Evidence (from `scripts/trace.py`).**

| Trace | Manila time | msgs | Tool calls | Stop | Cost |
|---|---|---|---|---|---|
| `87c692eb67ce3bc1` | 11:29 AM | 1 | 0 of 32 | end_turn | $0.088 |
| `8fe71cabafb188fa` | 6:37 PM | 1 | 0 of 32 | time_budget | $0.080 |
| `ca26391e1931500a` | 6:38 PM | 3 | 0 of 32 | end_turn | $0.054 |
| `49e2a46101cde826` | 6:40 PM | 5 | 0 of 32 | end_turn | $0.060 |
| `a59cbdb94d4127ec` | 6:42 PM | 7 | 0 of 32 | end_turn (message a) | $0.051 |
| `e41392abd3cc45e7` | 6:42 PM | 9 | 0 of 32 | end_turn (message b) | $0.048 |

All 6 messages ran on Sonnet 4.5 (`route=haiku`, flag off) with the same
`h_rules`, `h_snapshot` and `h_tools`. No message called a tool.

**Scope.** This is not an installment fix. The same failure can happen for
bills, receivables, set-asides, budgets, accounts and transactions. The plan
changes how Nudgy decides between the snapshot and the read tools, for every
entity at once. A deferral line in the snapshot is explicitly **not** the fix.

## 1. Root causes

None of these causes is specific to installments.

1. **The snapshot looks complete.** Each section lists some fields and does not
   say that the record has more. The installment line
   ([ai_coach_context.dart:961-964](../../lib/models/ai_coach_context.dart))
   shows name, account, monthly amount, months left and amount left. The model
   cannot tell "not in the summary" from "does not exist".
2. **The rules push against reads.** The only rule that sends the model to a
   read is "Answer from it alone only when it states the exact figure or fact".
   The model judged the installment line to be that fact. Many other sentences
   push the other way: "Do not run a search first", "every extra tool call is
   another round trip", "an unasked lookup makes the user wait", "Do not call it
   for a question the snapshot already answers". Most of them are about writes,
   but they read as general rules.
3. **The rules give an exit without a read.** Rule 3 gives a fixed reply ("I
   cannot verify this — that figure isn't in your current data.") that the model
   can use before it tries a tool.
4. **Tool descriptions list fields by hand, and the lists drift.** The `find`
   description lists "first and last payment month, interest, total interest and
   total payable" for installments. It does not list the deferral, which `find`
   returns.
5. **Nothing checks the turn.** A user who disputes an answer gets a second
   answer from the same snapshot. The model's own earlier "I can't see it" is in
   the history and anchors the next answer.

## 2. Rules that hold everywhere

1. **The snapshot never claims to be complete.** Every section that names
   records ends with a footer that says the record has more fields and names the
   call that returns all of them.
2. **No hand-written field lists.** A tool description says "returns every
   stored field". It does not list the fields, so it cannot drift.
3. **A dispute is never answered from the snapshot alone.** When the user says
   that an answer is wrong, or asks "can't you see X?", the turn makes a read call
   before it replies.
4. **Hints only where tools exist.** The on-device coach
   ([on_device_ai_coach_service.dart:382](../../lib/services/on_device_ai_coach_service.dart))
   uses the same `toPromptSummary()` and has no tools. It must not get footers
   that point to a tool.
5. **Measure first.** No prompt change ships without an eval run before and after
   it, on the same model, 2 runs each.
6. **Works on Sonnet 4.5, Sonnet 4.6 and Haiku 4.5.** Haiku matters because the
   routing flag (Plan 065 phase 5) sends lookups to it, and lookups are where this
   failure happens.

## 3. Phases

### Phase 1 — Eval cases (measure the failure first)

Extend `backend/ai-coach/evals/`. The runner already supports a 2-step question
(`then`) and checks the first tool call.

| Item | Detail |
|---|---|
| New set `index` | A third set in `questions.json`, reported apart, so its pass rate is visible on its own. The tuning set still decides the exit code. |
| Detail questions | 1 per record type that the snapshot names: bill, receivable, set-aside, budget, budget group, installment, account. Each asks for a detail that the snapshot leaves out. Pass: the first call is `find` for that record. |
| Name question | "the fridge" for a plan stored as "Panasonic Refrigerator". `find` matches by substring, so `query: "fridge"` returns not_found. Pass: the query uses the stored name, or there is no query (list all). Needs an `absent` input spec in the scorer. |
| Dispute questions | Multi-turn: a `history` with the user's question and an assistant reply that says "I can't see that", then the dispute. One in Taglish ("di mo ba makita?"). Pass: the first call of the dispute turn is a read. |
| Control questions | 3 questions that the snapshot answers exactly. Pass: no tool, and the figure in the text. This catches over-reading. |
| Fixture | Add a deferred "Panasonic Refrigerator" plan to `_context` in `test/utils/nudgy_eval_fixtures_test.dart`, then regenerate. |
| Baseline | Run twice on Sonnet 4.5, and once on Haiku 4.5. Record the numbers in section 10. Expected: detail and dispute cases fail today. |

16 new cases (a second, longer dispute was added after the first runs). One run
costs about $0.30 on Sonnet 4.5.

### Phase 2 — Snapshot footers and tool descriptions (one PR)

| Item | Detail |
|---|---|
| Footers | `AiCoachContext.toPromptSummary({bool readHints = false})`. When true, each section that names records ends with 1 line, for example `(summary only — every field of a plan, such as start month and deferral: find entity=installment)`. About 10 lines, about 200 tokens. The cloud advisor payload passes `readHints: true`. The on-device coach does not. |
| Examples, not lists | A footer may name 1 or 2 example fields so the model knows the kind of detail that exists, but it says "every field". The examples do not have to be complete. |
| `find` description | Replace the per-entity field list with "a found record comes back with every stored field". Remove "The snapshot names this month's records and their amounts only" (the footers now say it, next to the data). |
| Name matching | In the `find` description: "use the record's name as the snapshot lists it; on not_found, call again with no query to list them all". |
| Regenerate | `tools.json` and `snapshot.json` change; regenerate them in the same PR. |

A field manifest with a drift test (revision 1) is held back. Section 9 says why.
Build it only if the phase 2 eval shows that the model needs the field names.

### Phase 3 — Rule rewrite (one PR, same release as phase 2 if possible)

Changes in `_ADVISOR_SYSTEM_PREFIX`
([lambda_function.py:1390-1516](../../backend/ai-coach/lambda_function.py)):

1. **Replace the "WHEN TO CALL A READ TOOL" opening.** New rule: the snapshot is
   an index of records and totals. A question about any detail of one named
   record that its line does not state is answered with `find`. Keep the existing
   (a)–(d) cases. The rule must not depend on the footers, because an old app
   sends none.
2. **Add a dispute rule.** When the user says that an answer is wrong, or asks
   whether you can see something, call a read tool for that record before you
   reply. An earlier "I can't see it" in the conversation is not evidence.
3. **Narrow rule 3.** The fixed "I cannot verify this" reply is allowed only after
   a read call in the same turn returned nothing useful.
4. **Scope the anti-lookup sentences to writes.** "Do not run a search first",
   "an unasked lookup makes the user wait" and the same text in the `find`
   description apply to adding a new record only. Say so in the sentence.
5. **Reword the cost sentence.** Keep the point ("a wrong figure costs trust") and
   drop "One read call costs the user a second" as a reason not to read.
6. **Replace, do not add.** The rules block is about 3.9k tokens. The rewrite
   should leave it about the same size.

Ship only if the `index` set reaches 80% on both runs, and the tuning set and the
control cases do not fall.

### Phase 4 — Forced read on a dispute (only if phase 3 is not enough)

| Item | Detail |
|---|---|
| Client signal | New pure function in [advisor_routing.dart](../../lib/utils/advisor_routing.dart): `needsReadFirst(text, {required bool priorReplyHadNoRead})`. True when the message disputes the last answer or asks "can you see / can't you see", in English or Tagalog ("di mo ba makita", "wala ba", "check mo"), and the last assistant turn made no read. Sent as `read_first: true`. A false positive costs 1 read hop; a false negative leaves today's behaviour. |
| Lambda | When `read_first` is true, the first hop sends `tool_choice: {"type": "any"}`. Later hops are unchanged. |
| Trace | Log `guard=read` in the cost line and in `advisor_invocation`, so `trace.py` shows each time the guard fires. |
| Risk | `tool_choice: any` is not allowed with extended thinking. Sonnet 5.5 runs with `between_tools` thinking ([lambda_function.py:2490](../../backend/ai-coach/lambda_function.py)). On a 5.5 model the guard must skip, or turn thinking off for that hop. |
| Why the client | The routing words already live on the client. A server-side check on the reply text is worse: the reply has already streamed to the user. |

## 4. What this plan does not do

- No deferral line, or any other single-field patch, in the snapshot.
- No change to write tools or confirm cards.
- No change to which model a conversation uses.
- No server-side copy of the finance data. All reads stay on the phone.
- No change to where the briefing goes (PR #778, section 6).

## 5. Order and PRs

| PR | Phase | Base |
|---|---|---|
| 1 | Eval cases, `history` and `absent` support, fixture, baseline numbers | `dev` |
| 2 | Snapshot footers + `find` description | `dev` |
| 3 | Rule rewrite (Lambda) | `dev`, after PR 2 is deployed |
| 4 | Forced read (client + Lambda), only if the eval needs it | `dev` |

One PR per item, no bundles. PR 3 deploys with the Lambda on merge to `main`.
PR 2 needs an app build, so PR 3 must also read correctly for an old app.

## 6. Cost

**What one hop costs today.** Message (b) cost $0.0476 on Sonnet 4.5: 10,345
uncached input tokens ($0.031, 65%), 16,627 cache-read tokens ($0.005), 1,158
cache-write tokens ($0.004) and 482 output tokens ($0.007).

**What a read adds.** A read is one more hop with the same prefix, a short output
(the tool call) and a tool result of about 300–800 tokens:

| Model | One extra read hop | 60 extra hops a month |
|---|---|---|
| Sonnet 4.5 | about $0.04 | about $2.40 |
| Haiku 4.5 | about $0.013 | about $0.80 |

About 250 advisor hops a month cost about $9 today. If 1 message in 4 gains a
read, cost rises about 25%. Compare the failure: the installment conversation
used 5 messages ($0.29) and still gave a wrong answer. One read on message (a)
would have cost about $0.04.

**Footers.** About 200 tokens per hop: under $0.001.

**Latency.** The stream budget (38 s) is per hop, so more hops do not hit it. A
read hop has a short output, so it takes about the time to first token (2–3 s)
plus the phone's tool run.

**Why the snapshot is uncached.** The rules and tools are about 14k tokens and
are cached (13,380 written on the first message). The briefing (snapshot and
historical record, about 10k tokens for the real user) is billed uncached on
every hop. That is by design: PR #778 moved the briefing into the newest user
turn, so that a ledger edit rewrites only the last turn pair instead of the whole
conversation. It is not a bug, and this plan does not change it.

## 7. Open questions

1. Does the dispute rule (phase 3) alone pass on Haiku 4.5, or does Haiku need
   the forced read (phase 4)?
2. Should `getView (installments)` also show the deferral, so that a view and a
   `find` agree? (Plan 065 rule 4: one source for each figure.)
3. Why did the first message at 6:37 PM stop on `time_budget` with 1 output
   token after 38 s? This is outside this plan, but the trace shows it.

## 8. Decisions

Accepted by the developer on 2026-10-30 ("proceed" after the review):

1. Phase order: eval, then footers, then rules, then the guard if needed.
2. 80% threshold for the `index` set, the same as Plan 065.
3. No manifest unless the phase 2 eval needs it (section 9).

## 9. What revision 2 changed, and why

| Change | Reason |
|---|---|
| Manifest and drift test held back; footers say "every field" with examples | The drift came from lists. A description that lists nothing cannot drift, and a footer next to the data is the cue that the rules block lacked. The manifest adds a file and a test for 1 user, and is only needed if the model must see field names. The eval decides. |
| Footers only with `readHints: true` | The on-device coach uses the same text and has no tools. |
| Name matching in phase 1 and 2 | `find` matches by substring. The user said "fridge"; the plan is "Panasonic Refrigerator". A read with the user's word returns not_found, and the model gives up again. |
| Taglish dispute case and Tagalog words in phase 4 | The real dispute was Taglish ("eh?"). An English-only regex misses it. |
| 2 runs per measurement | One run of about 15 cases is noisy. A change ships when both runs pass. |
| Separate `index` set | Mixed into the tuning set, the new cases would hide in an overall rate. |
| Cost section rebuilt from the trace | Revision 1 said "under $1 a month". A read hop costs about $0.04 on Sonnet 4.5, because about 10k briefing tokens are billed uncached on every hop (by design, PR #778). |
| Eval runs on the production layout | The first baseline ran on a branch without PR #778 (rules hash `49bed87b`, production `80bbe004`). On that layout every dispute passed, so the eval did not show the real failure. On the production layout it does. Always check `h_rules` against the trace before a baseline. |
| "Replace, do not add" for the rules | The rules block is in every hop. |

## 10. Eval results

### Phase 1 baseline (2026-10-30, `index` set, 16 cases, rules `80bbe004`)

Same rules hash as production, with the briefing in the newest user turn
(PR #778).

| # | Case | Sonnet 4.5 run 1 | Sonnet 4.5 run 2 | Haiku 4.5 |
|---|---|---|---|---|
| 1 | installment-deferral | pass | pass | pass |
| 2 | installment-colloquial-name | FAIL (text) | pass | pass |
| 3 | bill-reminder (replaced bill-category, see below) | FAIL (text) | FAIL (text) | FAIL (text) |
| 4 | receivable-account | pass | FAIL (text) | FAIL (text) |
| 5 | setaside-account | pass | pass | pass |
| 6 | budget-repeats | pass | pass | pass |
| 7 | budget-group-members | pass | pass | pass |
| 8 | account-credit-limit | FAIL (text) | FAIL (text) | FAIL (text) |
| 9 | dispute-installment | pass | **FAIL (text)** | pass |
| 10 | dispute-repeated | pass | **FAIL (text)** | pass |
| 11 | dispute-bill | pass | pass | pass |
| 12 | dispute-setaside | pass | pass | pass |
| 13 | dispute-taglish | FAIL (text) | FAIL (text) | FAIL (find account, not receivable) |
| 14 | control-meralco | pass | pass | pass |
| 15 | control-iphone-months | pass | pass | FAIL (read it anyway) |
| 16 | control-japan-saved | pass | pass | pass |
| | **Pass rate** | **12/16 = 75%** | **10/16 = 62%** | **11/16 = 69%** |

Cost: about $0.34 and $0.29 per Sonnet run, $0.11 on Haiku.

What it shows:

1. **The real failure reproduces.** Run 2 answered both installment disputes
   (9, 10) from the briefing, as production did on 2026-10-30. Run 1 did not, so
   the failure is intermittent, which matches a model that is near the edge of
   its decision.
2. **It fails across record types, not only installments.** The bill (3) and
   the credit limit (8) fail on every run and both models. The receivable (4)
   fails on 2 of 3 runs. On the credit limit, Sonnet adds owed and available
   (₱60,000): a sum the rules say a tool must return.
3. **A Taglish dispute always fails** (13). On Sonnet it answers in text; on
   Haiku it reads the wrong record type.
4. **The controls hold on Sonnet.** Haiku over-reads once (15). The rule rewrite
   must not make this worse.
5. **Run-to-run noise is about 2 cases in 16.** A change ships only when both
   runs pass, as section 2 says.

**Case 3 was replaced after the first runs.** It asked for the Netflix bill's
category, but the recent-spending line states it ("Netflix — ₱549
(Entertainment, …)"), so Sonnet's text answer was correct. The new case asks for
the Globe bill's reminder, which only `find` returns. The dispute-bill history
moved to the same question. On the phase 1 fixture, bill-reminder fails 3 of 3
(Sonnet, Sonnet, Haiku) and dispute-bill passes 3 of 3, the same as the old
cases, so the pass rates above stand.

The briefing in the newest user turn sits right after the question. That makes
"answer from the briefing" the easy path in a dispute turn. The phase 2 footers
go inside the briefing, next to the data, which is the right place for them.

### Phase 2 (2026-10-30, read hints + `find` description, rules `80bbe004`)

| # | Case | Sonnet 4.5 run 1 | Sonnet 4.5 run 2 | Haiku 4.5 |
|---|---|---|---|---|
| 1 | installment-deferral | pass | pass | pass |
| 2 | installment-colloquial-name | pass | pass | pass |
| 3 | bill-reminder | FAIL (text) | FAIL (text) | pass |
| 4 | receivable-account | pass | pass | pass |
| 5 | setaside-account | pass | pass | pass |
| 6 | budget-repeats | pass | pass | pass |
| 7 | budget-group-members | pass | pass | pass |
| 8 | account-credit-limit | FAIL (text) | FAIL (text) | pass |
| 9 | dispute-installment | pass | pass | pass |
| 10 | dispute-repeated | pass | pass | pass |
| 11 | dispute-bill | pass | pass | pass |
| 12 | dispute-setaside | pass | pass | pass |
| 13 | dispute-taglish | FAIL (text) | pass | pass |
| 14 | control-meralco | pass | pass | pass |
| 15 | control-iphone-months | pass | pass | FAIL (read it anyway) |
| 16 | control-japan-saved | pass | pass | pass |
| | **Pass rate** | **13/16 = 81%** | **14/16 = 88%** | **15/16 = 94%** |

Older sets on Sonnet 4.5, one run: tuning 14/15 (the same as `dev` after
PR #778), held-out 5/5. Cost: about $0.30–0.35 per Sonnet run, $0.11 on Haiku.

Both installment disputes now pass on every run. Sonnet still answers the bill
reminder and the credit limit from the snapshot. The rule rewrite (phase 3)
targets those: a detail the line does not state, and a figure the model adds up
itself.
