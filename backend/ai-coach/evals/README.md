# Nudgy tool-choice eval (Plan 065 phase 2)

This eval asks the advisor model 15 finance questions. For each question it checks which tool the model calls **first**. It does not run the tools and it does not grade the answer text. The Dart tests check what each tool returns. This eval checks that the model picks the right tool.

The eval is not part of CI and it is not in the Lambda package. CI zips only `lambda_function.py`, `app.py` and `run.sh`.

## Files

| File | What it is |
|---|---|
| `questions.json` | The 15 questions, the acceptable first tool calls, and the pass threshold (80%). |
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
| `--only ID ...` | all | Run only these question ids. |
| `--threshold` | `0.8` (from `questions.json`) | Pass rate needed. |
| `--dry-run` | off | Print every request and make no calls. |

The progress goes to stderr. The table, the pass rate and the token count go to stdout, so `> result.md` gives a file to paste into a PR. The exit code is 0 at or above the threshold, 1 below it, and 2 when Bedrock refuses the call (for example, no access).

The request is built by the Lambda's own `_build_advisor_request` and `_generation_params`, with the Lambda's `max_tokens`, so the eval sends what production sends. The model is called with the default temperature, as in production, so two runs can differ by a question or two.

## Scoring

- `any`: the **first** `tool_use` of the reply must match one of the options. A correct tool in second place does not count.
- `all`: the reply must hold a `tool_use` for every option. This is the batch check: 2 writes in one message must come back in one reply.
- `then`: a canned `tool_result` goes back for every call of the first reply, and the next reply is scored. This is how "delete my gym bill" checks `find`, then `deleteBill` with the id from the result.

An option names the tool and the inputs that matter. An input spec is a literal (strings ignore case), `{"contains": s}`, `{"prefix": s}` or `{"any_of": [...]}`. An input that the option does not name can have any value.

## Cost

The plan budgets about **$1.50 per run** on Sonnet 4.5 ($3 / $15 per 1M tokens in / out). In practice the run costs less, because every request shares the same tools, rules and snapshot, and the prompt cache holds them. The first run on 2026-10-30 used 16 calls and cost about **$0.16** (13.6k tokens cache write, 199k cache read, 5k in, 2k out) in 60 seconds. The runner prints the token count and a cost estimate at the end of each run.

## Tests

```bash
BEDROCK_MODEL_ID=x python -m pytest evals -q
```
