# Plan 064 — Bedrock model migration (Haiku 5.5 + Sonnet 5.5)

**Goal:** move the AI coach off two Legacy models onto cheaper current ones, with no
downtime and an env-var-only rollback.

| Route | Today | Target | Price (Singapore, per 1M in/out) |
|---|---|---|---|
| `BEDROCK_MODEL_ID` — respond, food ops, image parsers, classifyFinance | `global.anthropic.claude-haiku-4-5-20251001-v1:0` | `global.anthropic.claude-haiku-5-5` | $1/$5 → $0.10/$0.50 |
| `ADVISOR_MODEL_ID` — adviseFinance (Nudgy) | `global.anthropic.claude-sonnet-4-5-20250929-v1:0` | `global.anthropic.claude-sonnet-5-5` | $3/$15 → $2/$10 (cache read $0.30 → $0.10) |

The live IDs were read from `food-coach-handler` with the `ifast-dev` AWS profile on
2026-10-29. The template and docs said Claude 3 Haiku; production ran Haiku 4.5.
Haiku 5.5 counts the same text as about 30% more tokens than Haiku 4.5, so the
real Haiku-tier saving is about 85-87%, not 90%.

Global routing was accepted for all ops on 2026-10-29. Neither 5.5 model has a geo
row in ap-southeast-1.

## Why the code must change (not only the env var)

1. **Thinking is on by default** on both 5.5 models. A response can start with a
   `thinking` block, so every `result["content"][0]["text"]` read breaks.
   Thinking tokens also bill as output.
2. **Turning thinking off differs per model.** Haiku 5.5: `{"type": "disabled"}`
   (effort `high` or below). Sonnet 5.5: `{"type": "disabled"}` is a 400; use
   `{"type": "between_tools"}` (effort `high` or below, no other field).
3. **Refusals.** Both can return `stop_reason: "refusal"` with no text.
4. **Thinking blocks are tied to the conversation.** Sonnet 5.5 returns progress
   notes between tool calls as `thinking` blocks. The advisor's system prompt
   (the snapshot) changes between turns and between hops, so a replayed block can
   fail the history-editing check. With `between_tools`, the guidance is to strip
   them from edited turns. We strip them everywhere: they hold progress notes
   only, never reasoning.

## Design — model-aware request params

`_generation_params(model_id, effort)` returns the extra body fields for the
model, and `{}` for any model it does not know. So:

- Code deploys first and is a no-op on Haiku 4.5 / Sonnet 4.5 (and Claude 3 Haiku).
- The switch is an env-var change on `food-coach-handler`.
- Rollback is the same env-var change in reverse.

Effort is env-configurable: `BEDROCK_EFFORT` (default `low`), `ADVISOR_EFFORT`
(default `medium`).

## PR 1 — Haiku tier (`feat/bedrock-haiku-5-5`, base `dev`)

- Add `_generation_params` and `_reply_text(result)` (joins `text` blocks, reads
  by type).
- Use both at all 5 Haiku-tier call sites: `_invoke_bedrock`, `_parse_food_from_image`,
  `_parse_receipt_from_image`, `_respond`, `_classify_finance`.
- `_respond`: a refusal (no text) returns a short fallback line, not an empty reply.
- Raise the 128-token caps to 256 (newer tokenizer; output is billed as emitted).
- Template, README, `docs/ai_coach_spec.md`: new model ID, and the model production really ran.
- Tests: params per model, text-by-type, refusal fallback.

## PR 2 — Advisor (`feat/bedrock-sonnet-5-5`, stacked on PR 1, base `dev`)

- `_generation_params` entry for Sonnet 5.5 → `between_tools` + effort.
- Strip `thinking` / `redacted_thinking` from replayed history in
  `_build_advisor_request`, and from `assistant_content` in both reply paths.
- Stream path: ignore `thinking_delta` / `signature_delta` (no crash, no delta frame).
- Refusal with no text → a short "can't help with that" line, `truncated: false`.
- Template default + description.
- Tests: stripping, refusal, stream with a thinking block.

## Manual steps (AWS profile `ifast-dev` — not done by CI)

1. Bedrock console (ap-southeast-1): confirm access to Haiku 5.5 and Sonnet 5.5.
2. IAM: add the two global profiles to the live function's inline policy
   (copy the `AdvisorBedrockInvoke` pattern: inference-profile ARN + the
   `foundation-model/anthropic.claude-*-5-5` ARNs in every Region).
3. After the PR's code is live: `update-function-configuration` on
   `food-coach-handler`. **It replaces the whole env map — read it first and put
   every key back.**
4. Watch CloudWatch `cost_line` (latency_ms, ttft_ms, out_tokens) for a day.

## Verify

- `pytest` in `backend/ai-coach`.
- After the env flip: one call per op from the app; check no 502s in logs.
