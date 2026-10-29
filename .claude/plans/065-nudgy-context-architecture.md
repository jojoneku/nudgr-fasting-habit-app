# Plan 065 — Nudgy v2: correct first, then reach, then cost

**Status:** approved, revision 3 (2026-10-29). Not built. The open decisions are settled (section 10).
- Revision 2 added web research, a Bedrock feature review, the ISV Day field guide
  and an audit of 302 advisor calls.
- Revision 3 is the result of a critical review: my own, plus an independent
  reviewer that had not seen the chat. Section 9 lists what changed and why.
  Section 10 lists the points that are still the developer's decision.

Supporting audit: [065a-nudgy-coverage-audit.md](065a-nudgy-coverage-audit.md).

**Scale check.** 1 user. About 250 advisor calls a month. About $9 a month,
paid by AWS credits. The best possible cost work saves about $5 a month. So this
plan puts **correctness and reach** first. Work that only saves cost waits for
paying users.

**Models that run today.** Sonnet 4.5 (advisor) and Haiku 4.5. The quota for
the 5.5 models is 0 (AWS denied it on 2026-10-29). Sonnet 4.5 reaches end of life
on 2027-04-08. Sonnet 4.6 has quota and the same price, and it is the fallback.
Every feature below must work on 4.5 or 4.6. A 5.5 feature is a bonus, not a
dependency.

## 1. Decision: no new agent framework (unchanged)

Nudgy is already an agent: one model, a tool loop and a 5-step limit. Both the
research and the reviewer agree that this is right.

| Option | Verdict |
|---|---|
| Bedrock Agents, AgentCore, multi-agent | No. They add cost and hops, and all data lives on the phone. |
| Knowledge Bases, vector RAG | No. The questions are exact sums over the user's own rows. |
| Intelligent Prompt Routing | Not possible. It supports Nova and Llama only. |
| Prompt Management | Not now. There are 2 prompts and 1 developer. |
| Server-side tools on Supabase | No, for chat. The math would exist twice, and Supabase lags the phone. |

## 2. Rules that hold everywhere

1. **Every write has a confirm card.** Nothing saves without an approve tap
   (design D3). This includes the quick-log fallback, which saves with no card
   today (audit 2.2), and no new path may skip the card.
2. **The model never calculates a figure.** The phone computes every number.
3. **One tool per write action.** Each tool keeps its own `AiToolKind`
   (create, update or destroy), as D11 requires. Only the read tools merge.
4. **One source for each figure.** If 2 screens show different values for the
   same concept, fix the presenter. Do not pick a winner in a tool.
5. **A feature works on Sonnet 4.5 or 4.6.**

## 3. Phases

### Phase 1 — Correctness (small PRs, first)

| PR | Content | Why first |
|---|---|---|
| 1a | Fix the card/save mismatches in audit 2.1 #1–6. Fix the double record on `markBillPaid` (#7). Make the delete card name the transfer partner and installment plan that are also deleted (#8). Refuse an unknown id before the card (#9). Show a card on the quick-log fallback (2.2). | Today the user approves one thing and the app saves another |
| 1b | Read errors. The `findTransactions` spend total uses `isSpendingOutflow`. Fix the `findBudgets` savings rows. Find tools default to today's month, not the tab's month. Fix the wrong "not retained" prompt text, the income category shown as spending, and the trend labels with no year. **Make the 3 budget totals and the 3 "saved" figures (audit 1.3) agree at the presenter level, or label each with its definition.** | Nudgy gives wrong numbers today |
| 1c | Stop button (section 6) | A small change that the user asked for |
| 1d | **Routing: veto, not replace.** Add a planning-word veto (want, plan, should, if, how, next, thinking) to `looksLikeExpenseLog` and `recognisesLoggableEntry`. Add a "Not a log — ask Nudgy" button on the quick-log card. | It fixes the misroutes the user reported in about 1 hour. Quick log stays instant. |
| 1e | **Cache split.** System block = [rules] + [snapshot + historical], with a breakpoint after each. A ledger edit then keeps the tools and rules (about 9k tokens) in the cache. | Takes a few hours, and fixes most of the "edit rewrites the cache" cost |

### Phase 2 — Measure (small)

- Add these to `cost_line`: `trace_id` (made by the phone for each message), tool
  names, the result status of each tool, the hop count, and hashes of the rules,
  the snapshot and the tool blocks.
- If the hashes are the same but the cache still misses, global routing caused it.
  A different snapshot hash means the snapshot caused it. This answers the routing
  question. A region test is not possible: from Singapore, the 4.5 models have only
  the `global.` profile.
- **Tests, in 2 parts:**
  - Deterministic Dart unit tests, at no cost: `find` matching, the `queryFinance`
    results, and the mapping from card to saved record. These run on a fixed
    fixture dataset, not on live data.
  - About 15 model-in-the-loop questions that check the tool choice only, with a pass
    threshold. Start from the 10 failing questions in audit 1.4. One run costs about $1.50.

### Phase 3 — Reach (the main quality gain)

| Item | Detail |
|---|---|
| `find` replaces the 7 `find*` tools | `find(entity, query, month)`. Match on all words in any order, ignore filler words, and return the nearest names on `not_found`. Status is found / not_found / ambiguous / error, with a fix hint. **If exactly 1 row matches, return all its fields** (bill: paid date, paid amount, account, note, linked transaction, series). Then no separate `getDetails` hop is needed. |
| `queryFinance` | A group-by tool: metric, groupBy, filters, from/to, top. The phone computes the result. It uses the same rules as the presenters (`isSpendingOutflow`, transfers, installments). |
| `getView` for 2 screens | Dashboard and Budget only. They answer "budget left", forecast and pace. Add other screens when a test question fails, not before. |
| `createdAt` | Add it to `Bill`, `TransactionRecord`, `Receivable` and `BudgetedExpense`. It is set on create and synced in the JSON, so no table change is needed. Old records report "before <release>". The user asked exactly this question. The cost is small, because the JSON carries the field. |

After phase 3, one question has one tool path:

| Question type | Tool |
|---|---|
| A named record and its details | `find` |
| Rows in a period | `findTransactions` |
| A screen's figure | `getView` |
| A sum or group-by that no screen shows | `queryFinance` |

The tool descriptions must say this table, so the model does not pick 2 paths
that give 2 numbers.

### Phase 4 — Batch review + action parity (one design, built together)

The batch review and parity both depend on the tool shape and the tiers, so they
merge into one phase.

**Batch review (layout decided in section 10: one vertical list):**
- All write calls in one Nudgy step become one batch.
- `EntryReviewCard` is generalised to every entity type: a vertical list,
  each row expands to edit inline with the existing pickers, Remove on each row,
  and a sticky **Approve all (N)** button.
- **Revise by chatting in the main chat.** If the user types while a batch is
  open, every pending call returns "not approved; the user said: …". Nudgy then
  proposes a new batch in one hop. There is no sub-session and no `reviseBatch` tool,
  and Nudgy keeps the full context.
- **An open batch survives an app restart.** A `tool_use` must always get a
  `tool_result`. If the batch is lost, the pending calls return "not reviewed".
- **Edits that need a lookup take 2 steps:** `find`, then the batch. The prompt
  rule is "propose all changes in one step **after** the lookups".

**Parity:** add the missing actions as separate tools (rule 3), most-asked first:
- mark unpaid / not received
- fund a set-aside
- installment month paid / edit plan
- budget set / edit / remove
- account edit
- category add
- bulk mark paid

Grocery and account delete wait. Import, export and settings never go through Nudgy.

**Tiers decide the card, not whether a card appears:**

| Tier | Card |
|---|---|
| T1 create | Normal row in the batch |
| T2 edit or money move | Row shows before → after |
| T3 delete, bulk or later months | Red row. It lists what else changes, keeps the scope control (D4), and Approve all asks once more |

Undo is the existing ledger undo for transaction deletes. A general undo of every
action waits, because undo after sync risks a last-write-wins overwrite (July audit).

### Phase 5 and later — only with paying users

| Item | Why it waits |
|---|---|
| Briefing in the latest user turn | Saves cost, not quality. When it ships, send the **full** briefing on each turn, never deltas. |
| Memory | Use the existing `AdvisorConversation`. Start a new conversation after a long idle gap, and trim the history in chunks (drop 20 when it passes 50). No Haiku summary, because a summary loses numbers. |
| Haiku routing | Route **per conversation**, not per turn, so the 2 models do not each write a cache of the same history. It needs Haiku quality data from the tests. |
| 1h TTL on the rules + tools | Pays off only when many users share the prefix |
| Invocation logs, `logEvent` op, trace script, per-user cost header, Guardrails | Useful with more than 1 user. With 1 user, the developer can reproduce any problem on his own phone. Add a privacy-policy line first. |

## 4. Prompt layout (target, for phase 5)

| Layer | Content | Cache |
|---|---|---|
| Tools + rules | Tool catalogue, `_ADVISOR_SYSTEM_PREFIX` | Breakpoint 1 |
| Profile | Profile facts | Breakpoint 2 |
| Chat | History, never edited | Breakpoint 3 (2nd-to-last user turn) |
| Briefing | Full, about 1k tokens, in the latest user turn only. It is removed from older turns, which costs only a rewrite of the last turn pair. | Not cached |

Thinking blocks: `_without_thinking` strips them because the system block changes
on each turn. When the briefing moves out of the system block, decide whether to
keep thinking blocks on Sonnet 5.5 `between_tools`.

## 5. Tool cost, corrected

Tool definitions sit in the cached prefix. Reading 6k tokens from the cache costs
about $0.002 for each turn, or about $0.50 a month. Adding tools for parity costs
cents. The real cost of more tools is **wrong tool choice**, and the tests in
phase 2 measure that. Revision 2 said "71% of turns pay for all 25 tools". That
claim ignored the 0.1× cache-read price.

## 6. Stop button

- While Nudgy works, the send button becomes a stop button (44×44, in
  `ai_chat_sheet.dart`, which the web dock reuses).
- Stop cancels the stream subscription. The generator's `finally` closes the
  HTTP client.
- The partial text stays and is marked "Stopped". No next hop starts. An open
  batch returns "not approved".
- A `tool_use` with no result is not replayed.
- Bedrock may finish the reply after a disconnect. The worst case is about $0.045
  for each stop, so no Lambda change is needed now.

## 7. Cost (estimates, Sonnet 4.5)

| | Today | After phase 1 | After phase 5 |
|---|---|---|---|
| Cost per message | ~$0.05 | ~$0.045 (cache split) | ~$0.025 |
| Monthly at current use | ~$9 | ~$8.5 | ~$5–6 |

## 8. Open questions

- Do Bedrock InvokeModel and Sonnet 4.5 accept `strict: true` and `input_examples`
  on tools? Test this with one call before phase 3 depends on it.
- Haiku 4.5 caches only prefixes of 4,096 tokens or more. The Haiku ops prompts may
  never cache. Check this in a separate task.

## 9. What revision 3 changed, and why

| Revision 2 said | Revision 3 says | Reason |
|---|---|---|
| T1 changes are applied at once, with Undo | Every write has a card | It broke D3, and it brought back the "save with no card" bug that phase 1 fixes. Undo after sync risks an overwrite. With Approve all, the saving is 1 tap. |
| One write tool per entity with an `action` field | One tool per write action | Revision 2 contradicted itself. One tool loses the create/destroy split (D11), and it makes a large union schema that may fail strict mode. The token saving is about $0.50 a month. |
| Briefing with deltas | Full briefing on each turn, in phase 5 | With deltas the model must add up numbers. A summary deletes the base. History is saved as text only. A full briefing costs about $0.75 a month. |
| Rolling Haiku summary | New conversation after idle, chunked trim | A summary loses numbers and adds a call. |
| Nudgy-first routing | Planning-word veto + "ask Nudgy" button | Nudgy-first moves each log to Sonnet: about 8 s slower, and up to about $6 a month more. The veto fixes the reported cases in about 1 hour. |
| Refine sub-session with `reviseBatch` | Revise in the main chat | The sub-session loses the main context, needs its own tools, uses up the daily cap, and adds items that have no `tool_use` id. |
| `getView` for 6 screens + a PR rule | `getView` for 2 screens; more when a test fails | Nothing enforces the PR rule. The other screens answer no failing question. |
| `getDetails` as its own tool | `find` returns all fields for a single match | Saves a hop of about 4 s. |
| Full audit trail, invocation logs, `logEvent` now | `trace_id` + tool names and statuses now; the rest waits for a second user | The developer is the only user. Full bodies put finance text in CloudWatch. |
| A golden set of 40 questions on live data | Free Dart tests on fixture data + 15 model questions | Live answers change every day. Each run of 40 questions costs about $4. |
| Cache split "does not help" | Cache split in phase 1 | It keeps the tools and the rules (about 9k tokens) cached after an edit. My earlier claim was half wrong. |
| Briefing, memory and routing as core phases | Deferred to paying users | They save about $5 a month. |
| "Phase 0" | Removed | It did not exist in the phase list. |

## 10. Decisions (accepted by the developer on 2026-10-29)

The developer accepted all 5 recommendations below:
1. One vertical list for any number of batch items.
2. Revise the batch in the main chat, with no sub-session.
3. A card for every write.
4. The routing veto first.
5. A minimal trace now.

The reasons are kept below for the record.

1. **Batch layout.**
   - The user proposed: swipe cards for 1–3 items, a table for 4 or more.
   - I recommend: one vertical list for all counts, with rows that expand.
   - Reasons:
     - Swipe cards hide items 2 and 3. Approve all can then save items the user never saw.
     - 2 layouts mean 2 code paths on mobile and web, and twice the tests.
     - A table with 5 columns and 2 buttons of 44 px does not fit 343 px of usable phone width.
     - `EntryReviewCard` already works this way for transactions.
   - If the swipe cards stay, Approve all must stay off until every card has been seen.
2. **Refine sub-session** (see section 9). I recommend revising in the main chat.
3. **Low-risk changes with no card.** I recommend a card for every change, with
   one-tap Approve all. Revisit only when the tests show more than 95% accuracy over a month.
4. **Nudgy-first routing.** I recommend the veto first. Move to Nudgy-first only if
   the "ask Nudgy" taps show that the veto is not enough.
5. **Full audit trail now.** I recommend `trace_id` and statuses now, and the rest
   when a second user joins.
