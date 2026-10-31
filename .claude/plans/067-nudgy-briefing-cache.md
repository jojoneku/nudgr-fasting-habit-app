# Plan 067 — Cache the Nudgy briefing across messages, then slim it

Date: 2026-10-31. Follows Plan 065 phase 5 and Plan 066.

## Why

Plan 065 phase 5 moved the briefing (snapshot + historical record) out of the
system prompt and into the newest user turn. The reason: a ledger edit then
rewrote only the last turn pair, not the whole conversation. That design
assumed the briefing was about 1k tokens and changed with most messages.

The logs (`advisor_invocation`, 2026-10-24 to 2026-10-31) say otherwise:

| Fact | Value |
|---|---|
| Briefing size, real user | about 22k characters, about 10k tokens |
| Messages sent less than 5 min after the previous one | 15 |
| ...with the same `h_snapshot` as the previous message | 14 |
| Cache write on a warm message today | 11–13k tokens (the briefing again) |
| Cache write on a warm message before phase 5 (2026-10-30 10:38–10:42) | 0.3–2k tokens |

So the briefing is written to the cache again on almost every message,
although it did not change. That is about $0.035 per warm message on Sonnet 4.5.

## A — the briefing in the system prompt, the reminder after the question

1. The system prompt becomes:
   - block 1: rules (breakpoint 1, as now);
   - block 2: date + profile + briefing (breakpoint 2).
2. The newest user turn ends with a short reminder block (`<briefing-reminder>`):
   the `_BRIEFING_REMINDER` text, which tells the model the briefing is a
   summary and to apply WHEN TO CALL A READ TOOL. It stays the last thing the
   model reads before it answers. That property is what took the eval from
   10/15 back to 15/15 in phase 5.
3. Breakpoints 3 and 4 stay on the last 2 user turns.
4. `_without_briefing` also strips a replayed reminder block.
5. `h_snapshot` hashes system block 2, which now holds the briefing.

Trade-off: when the briefing changes, everything after it is written again,
the conversation included. At 1 change in 15 warm messages, and with a
conversation that is small next to a 10k briefing, this costs much less than
a 10k write on every message.

Expected cost per warm 1-hop message: about $0.02 (was about $0.055).

### Verify A

- `pytest` in `backend/ai-coach` (test_cache, test_app, evals tests).
- Eval: `python evals/run_eval.py --set all`. Pass: tuning >= 80%, and the
  `index` set no lower than the last run on dev.
- After deploy: 3 messages less than 5 min apart; cache write on messages 2–3
  must be about 1–2k, not about 11k.

## B — slim index (after A is live)

With A, a warm message reads the briefing at 0.1x, so a smaller briefing saves
money mostly on cold messages (about 1 in 3 first hops in the last 7 days).

Candidates, by size (`scripts/briefing_sizes.py --hours 48`):
`hist_biggest` 19%, `recent_txns` 18%, `hist_categories` 9%.

Cost model with A in place (Sonnet 4.5), for a cut of about 3k tokens:

| Case | Saving or cost |
|---|---|
| Cold message | saves about $0.011 |
| Warm message | saves about $0.001 |
| Message that now needs a read for the removed data | costs about $0.015 and 3–5 s |

Average saving: about $0.004 per message, before the cost of extra reads.
B loses money when more than about 1 in 4 messages needs the removed data.
In the 2026-10-31 test, 2 of 4 messages used `hist_biggest`.

Decision: build B only if the A numbers after deploy show a cold-message share
or a briefing size much larger than above. Otherwise drop B and keep the
full briefing, which also keeps answers fast.

Also fix `_CHARS_PER_TOKEN` in `scripts/briefing_sizes.py` (3.5 → 2.2,
measured from the 2026-10-31 cache writes).
