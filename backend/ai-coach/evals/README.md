# Nudgy tool-choice eval (Plan 065 phase 2)

This eval asks the advisor model 15 tuning questions and 5 held-out questions about finance. For each question it checks which tool the model calls **first**. It does not run the tools. It reads the answer text only when the snapshot states the exact figure, so an answer without a tool is correct (see Scoring). The Dart tests check what each tool returns. This eval checks that the model picks the right tool.

The eval is not part of CI and it is not in the Lambda package. CI zips only `lambda_function.py`, `app.py` and `run.sh`.

## Files

| File | What it is |
|---|---|
| `questions.json` | The 15 tuning questions (`questions`), the 5 held-out questions (`holdout`), the acceptable first tool calls, and the pass threshold (80%). |
| `tools.json` | `financeToolsRequestJson()`: the tool catalogue the app sends. Generated. |
| `snapshot.json` | The `context` the app sends (`summary` + `historical`) for a fixed, made-up user on 2026-10-15. Generated. No real user data. |
| `run_eval.py` | The runner. It calls Bedrock and prints a Markdown table. |
| `scoring.py` | The scorer. Pure functions, no network. |
| `test_scoring.py` | pytest for the scorer, the fixtures and the runner (with a fake Bedrock). |

## Regenerate the fixtures

`test/utils/nudgy_eval_fixtures_test.dart` fails when `kFinanceTools` or the snapshot renderer changes and the JSON is old. Regenerate both files from the repository root:

```bash
flutter test test/utils/nudgy_eval_fixtures_test.dart --dart-define=UPDATE_EVAL_FIXTURES=true
```

The snapshot is built from an `AiCoachContext` in that test, through `CloudAiCoachService.advisorPayload`, which is the code the app uses. To change the made-up user, edit `_context` in the test and regenerate.

## Run

You need the `ifast-dev` AWS profile with `bedrock:InvokeModel` on the model. The eval changes nothing in AWS. Run from `backend/ai-coach/`:

```bash
python evals/run_eval.py
```

```bash
python evals/run_eval.py --model sonnet-4.6
```

```bash
python evals/run_eval.py --dry-run
```

| Option | Default | Meaning |
|---|---|---|
| `--model` | `global.anthropic.claude-sonnet-4-5-20250929-v1:0` (production) | A model or inference profile id, or `sonnet-4.5` / `sonnet-4.6`. |
| `--profile` | `ifast-dev` | AWS profile. |
| `--region` | `ap-southeast-1` | Bedrock region. |
| `--set` | `all` | `tuning`, `holdout`, `index` or `all`. With `all`, each set gets its own table and pass rate. |
| `--only ID ...` | all | Run only these question ids. |
| `--threshold` | `0.8` (from `questions.json`) | Pass rate needed. |
| `--dry-run` | off | Print every request and make no calls. |

The progress goes to stderr. The table, the pass rate and the token count go to stdout, so `> result.md` gives a file to paste into a PR. The exit code is 0 when the tuning set is at or above the threshold (another set when it runs alone), 1 below it, and 2 when Bedrock refuses the call (for example, no access).

The request is built by the Lambda's own `_build_advisor_request` and `_generation_params`, with the Lambda's `max_tokens`, so the eval sends what production sends. The model is called with the default temperature, as in production, so two runs can differ by a question or two.

## Scoring

- `any`: the **first** `tool_use` of the reply must match one of the options. A correct tool in second place does not count.
- `some`: a `tool_use` in **any** position of the reply must match one of the options. Use it only for a two-part question, where the calls of one reply run together and their order changes nothing.
- `all`: the reply must hold a `tool_use` for every option. This is the batch check: 2 writes in one message must come back in one reply.
- `then`: a canned `tool_result` goes back for every call of the first reply, and the next reply is scored. This is how "delete my gym bill" checks `find`, then `deleteBill` with the id from the result.
- `history`: earlier turns (`{"role": "user" | "assistant", "text": ...}`) sent before the question, starting with the user and ending with the assistant. This is how a follow-up ("you can't see it?") is scored.

An option names the tool and the inputs that matter. An option can instead be `{"answer": [text, ...]}`: the reply makes no tool call, and its text holds every listed text. Use it only when the snapshot states the exact figure under the name the user uses. An input spec is a literal (strings ignore case), `{"contains": s}`, `{"prefix": s}`, `{"any_of": [...]}` or `{"absent": true}` (the call leaves the key out, as `find` with no query does to list every record). An input that the option does not name can have any value.

## Snapshot-vs-read questions (Plan 066)

The `index` set checks one thing: does the model read a record's details with a tool, instead of trusting the snapshot summary? It has 3 kinds of question:

- **Detail**: one per record type that the snapshot names. Each asks for a detail that the snapshot leaves out.
- **Dispute**: a `history` where the assistant said it cannot see something, then the user pushes back. One is in Taglish.
- **Control**: the snapshot states the answer exactly. A read here is waste, so only a text answer passes. These catch a prompt change that makes the model read everything.

Run it on its own with `--set index`.

## Held-out questions

The `holdout` questions check that a prompt change did not over-fit to the tuning questions. Do not change the prompt or a tool description because of a held-out result. When you tune, run `--set tuning`, and run `--set all` only at the end. When a held-out question has served for tuning, move it to `questions` and write a new held-out question.

## Cost

The plan budgets about **$1.50 per run** on Sonnet 4.5 ($3 / $15 per 1M tokens in / out). In practice the run costs less, because every request shares the same tools and rules, and the prompt cache holds them. The first run on 2026-10-30 used 16 calls and cost about **$0.16** (13.6k tokens cache write, 199k cache read, 5k in, 2k out) in 60 seconds. From phase 5 the snapshot was in the user turn and was not cached, so each call paid for it as input: a run of all 20 questions cost about **$0.42** (17k cache write, 254k cache read, 81k in, 2.5k out). Since Plan 067 the snapshot is in the system prompt and cached: a run of all 38 questions costs about **$0.36–0.41** (24–36k cache write, about 700k cache read, 131 in, 4k out). The runner prints the token count and a cost estimate at the end of each run.

## Tests

```bash
BEDROCK_MODEL_ID=x python -m pytest evals -q
```
