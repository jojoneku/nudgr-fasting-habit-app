"""
build_food_aliases.py — Generate colloquial aliases + descriptive phrases
for every row in assets/food_db.sqlite.

Runs the local `claude -p` CLI in subprocess (uses your Claude Code
subscription — no API key required). Output is sharded so re-running
picks up where it left off.

Usage:
    python scripts/build_food_aliases.py              # full run
    python scripts/build_food_aliases.py --dry-run    # first 100 entries only
    python scripts/build_food_aliases.py --batch 40   # custom batch size
    python scripts/build_food_aliases.py --resume     # explicit resume (default)
    python scripts/build_food_aliases.py --merge-only # skip generation, just merge shards
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

# Default Bedrock model — Sonnet 4.6 via APAC cross-region inference profile.
# Override with --model or BEDROCK_MODEL_ID env var.
DEFAULT_BEDROCK_MODEL = os.environ.get(
    "BEDROCK_MODEL_ID",
    "global.anthropic.claude-sonnet-4-6",
)
DEFAULT_BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "ap-southeast-1")

# Resolve the `claude` CLI entry point. On Windows, npm installs a `.cmd`
# shim that subprocess can't find without help; shutil.which handles this.
# Only required when --backend cli is selected.
def _resolve_claude_bin():
    p = shutil.which("claude")
    if p is None:
        sys.exit(
            "claude CLI not found on PATH. Install Claude Code and ensure "
            "`claude --version` works in your shell, or use --backend bedrock."
        )
    return p

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "assets" / "food_db.sqlite"
SHARD_DIR = ROOT / "scripts" / "data" / "aliases_shards"
OUTPUT_PATH = ROOT / "assets" / "data" / "food_aliases.json"

# Few-shot examples baked into the prompt. One Filipino food, one Western,
# one ambiguous case — anchors the model on style + length + JSON format.
FEW_SHOT = """\
Example input:
[
  {"id":"ex1","name":"Pork Belly, Cooked","category":"Pork"},
  {"id":"ex2","name":"Fettuccine Alfredo","category":"Pasta"},
  {"id":"ex3","name":"Rice, White, Cooked","category":"Grains"}
]

Example output:
{
  "ex1": ["fried pork", "lechon kawali", "crispy pork belly", "liempo", "pork belly fried", "roast pork belly", "deep fried pork", "pork crackling"],
  "ex2": ["creamy chicken pasta", "alfredo pasta", "creamy pasta", "white sauce pasta", "fettuccine in cream sauce", "pasta alfredo", "creamy fettuccine"],
  "ex3": ["kanin", "white rice", "cooked rice", "plain rice", "steamed rice", "boiled rice"]
}
"""

INSTRUCTIONS = """\
You are augmenting a food database with colloquial aliases and short
descriptive phrases that users naturally type when logging meals.

For each food below, output 8 to 12 short phrases someone might type
to mean that food. Include:
- Direct synonyms / alternate names
- Common cooking variations (fried / grilled / baked) when sensible
- Filipino names where natural (kanin, adobo, sinigang, lechon, etc.)
- Brief descriptive phrases people actually type
- Very common misspellings only if frequent in the wild

DO NOT include:
- The original name verbatim (already indexed separately)
- Hyper-specific brand names
- Aliases that would collide with a fundamentally different food
  (e.g., do not tag "chicken" as alias for any pork dish)
- Made-up regional names you are not confident about

Output STRICT JSON only — no markdown fences, no preamble, no commentary.
Keys are the input ids; values are arrays of strings.
"""

# ── Subprocess invocation ─────────────────────────────────────────────────────


_CLAUDE_BIN: str | None = None


def run_claude_cli(prompt: str, timeout: int = 180) -> str:
    """Run `claude -p` with prompt piped via stdin. Returns stdout."""
    global _CLAUDE_BIN
    if _CLAUDE_BIN is None:
        _CLAUDE_BIN = _resolve_claude_bin()
    result = subprocess.run(
        [_CLAUDE_BIN, "-p"],
        input=prompt,
        capture_output=True,
        text=True,
        timeout=timeout,
        encoding="utf-8",
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"claude -p exited {result.returncode}: {result.stderr.strip()[:500]}"
        )
    return result.stdout


_bedrock_client = None


def _get_bedrock_client(region: str):
    global _bedrock_client
    if _bedrock_client is None:
        import boto3  # imported lazily so --backend cli doesn't need boto3
        from botocore.config import Config

        # Sonnet at batch=100 with ~4K output tokens can take 60–180s on first
        # response. boto3's default 60s read timeout kills these. Bump way up.
        cfg = Config(
            read_timeout=300,
            connect_timeout=10,
            retries={"max_attempts": 3, "mode": "standard"},
        )
        _bedrock_client = boto3.client(
            "bedrock-runtime", region_name=region, config=cfg
        )
    return _bedrock_client


def run_bedrock(
    prompt: str,
    *,
    model_id: str = DEFAULT_BEDROCK_MODEL,
    region: str = DEFAULT_BEDROCK_REGION,
    max_tokens: int = 8000,
) -> str:
    """Direct Bedrock invocation via boto3. ~10x faster than the Claude Code
    CLI because it skips the entire CLI bootstrap. Requires AWS credentials
    on the standard chain (env / ~/.aws / SSO)."""
    client = _get_bedrock_client(region)
    response = client.invoke_model(
        modelId=model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(
            {
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": max_tokens,
                "messages": [{"role": "user", "content": prompt}],
            }
        ),
    )
    result = json.loads(response["body"].read())
    return result["content"][0]["text"]


def run_backend(prompt: str, backend: str, model_id: str, region: str) -> str:
    if backend == "cli":
        return run_claude_cli(prompt)
    if backend == "bedrock":
        return run_bedrock(prompt, model_id=model_id, region=region)
    raise ValueError(f"unknown backend: {backend}")


_FENCE_RE = re.compile(r"```(?:json)?\s*(.*?)\s*```", re.DOTALL)


def extract_json(text: str) -> dict[str, list[str]]:
    """Tolerant JSON extractor — handles bare JSON, fenced blocks, or
    JSON embedded in chatty output."""
    text = text.strip()
    if not text:
        raise ValueError("empty output")

    # Strip any markdown fences if present.
    m = _FENCE_RE.search(text)
    if m:
        text = m.group(1).strip()

    # Try direct parse first.
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Fallback: find the outermost {...} block.
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError(f"no JSON object in output: {text[:200]}")
    return json.loads(text[start : end + 1])


# ── Batch processing ──────────────────────────────────────────────────────────


def load_entries() -> list[dict[str, str]]:
    if not DB_PATH.exists():
        sys.exit(f"food DB not found at {DB_PATH}")
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT id, name, category FROM foods ORDER BY rowid"
        ).fetchall()
    finally:
        conn.close()
    return [{"id": r[0], "name": r[1], "category": r[2] or ""} for r in rows]


def build_prompt(batch: list[dict[str, str]]) -> str:
    entries_json = json.dumps(
        [{"id": e["id"], "name": e["name"], "category": e["category"]} for e in batch],
        ensure_ascii=False,
        indent=2,
    )
    return f"{INSTRUCTIONS}\n\n{FEW_SHOT}\nFoods to alias:\n{entries_json}\n"


def process_batch(
    batch: list[dict[str, str]],
    shard_path: Path,
    *,
    backend: str = "bedrock",
    model_id: str = DEFAULT_BEDROCK_MODEL,
    region: str = DEFAULT_BEDROCK_REGION,
    max_retries: int = 2,
) -> dict[str, list[str]]:
    prompt = build_prompt(batch)
    last_err: Exception | None = None
    for attempt in range(max_retries + 1):
        try:
            raw = run_backend(prompt, backend, model_id, region)
            parsed = extract_json(raw)
            # Sanity: every id in batch should be a key.
            missing = [e["id"] for e in batch if e["id"] not in parsed]
            if missing:
                raise ValueError(f"missing ids in response: {missing[:5]}...")
            # Normalize: dedupe, lowercase, drop empties.
            cleaned = {
                fid: dedupe([s.strip().lower() for s in arr if s and s.strip()])
                for fid, arr in parsed.items()
            }
            shard_path.parent.mkdir(parents=True, exist_ok=True)
            with shard_path.open("w", encoding="utf-8") as f:
                json.dump(cleaned, f, ensure_ascii=False, indent=2)
            return cleaned
        except Exception as e:
            last_err = e
            if attempt < max_retries:
                # Add a stricter reminder on retry.
                prompt = (
                    "REMINDER: respond with valid JSON only, no markdown, "
                    "no commentary. Every id in the input must appear in the output.\n\n"
                    + prompt
                )
                time.sleep(2 + attempt * 3)
    raise RuntimeError(f"batch failed after retries: {last_err}")


def load_done_ids() -> set[str]:
    """Union of all food_ids covered by existing shards. Lets the script
    survive batch-size changes — resume is keyed on entry ids, not shard
    indices."""
    done: set[str] = set()
    if not SHARD_DIR.exists():
        return done
    for shard in SHARD_DIR.glob("batch_*.json"):
        try:
            with shard.open("r", encoding="utf-8") as f:
                done.update(json.load(f).keys())
        except Exception as e:
            print(f"  warning: could not read {shard.name}: {e}")
    return done


def next_shard_path() -> Path:
    """First batch_NNNNN.json slot that doesn't exist yet."""
    for i in range(100000):
        p = SHARD_DIR / f"batch_{i:05d}.json"
        if not p.exists():
            return p
    raise RuntimeError("ran out of shard slots")


_reserve_lock = threading.Lock()


def reserve_shard_path() -> Path:
    """Atomically pick an unused shard path AND create a placeholder so the
    next concurrent caller picks a different slot. The actual JSON write
    overwrites the placeholder on success; on failure the empty file is
    cleaned up by the caller."""
    with _reserve_lock:
        path = next_shard_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()
        return path


def dedupe(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for it in items:
        if it not in seen:
            seen.add(it)
            out.append(it)
    return out


# ── Merge + validation ────────────────────────────────────────────────────────


def merge_shards() -> dict[str, list[str]]:
    merged: dict[str, list[str]] = {}
    if not SHARD_DIR.exists():
        return merged
    for shard in sorted(SHARD_DIR.glob("batch_*.json")):
        with shard.open("r", encoding="utf-8") as f:
            data = json.load(f)
        merged.update(data)
    return merged


def validate(merged: dict[str, list[str]], all_ids: list[str]) -> None:
    missing = [fid for fid in all_ids if fid not in merged]
    if missing:
        print(f"WARNING: {len(missing)} entries have no aliases (first 10): {missing[:10]}")
    thin = [fid for fid, arr in merged.items() if len(arr) < 6]
    if thin:
        print(f"WARNING: {len(thin)} entries have fewer than 6 aliases (first 10): {thin[:10]}")
    # Count collisions: same alias appearing in >1 food id.
    inverse: dict[str, list[str]] = {}
    for fid, arr in merged.items():
        for a in arr:
            inverse.setdefault(a, []).append(fid)
    collisions = {a: ids for a, ids in inverse.items() if len(ids) > 3}
    if collisions:
        print(f"NOTE: {len(collisions)} aliases used by >3 foods (likely too generic).")
        for a, ids in list(collisions.items())[:5]:
            print(f"  '{a}' -> {len(ids)} foods")


# ── Main ──────────────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="process first 100 entries only")
    ap.add_argument("--batch", type=int, default=100, help="entries per model call")
    ap.add_argument("--merge-only", action="store_true", help="skip generation, just merge shards into output")
    ap.add_argument(
        "--backend",
        choices=["bedrock", "cli"],
        default="bedrock",
        help="bedrock (boto3, fast, ~$5/run) or cli (claude -p, free, slow)",
    )
    ap.add_argument(
        "--model",
        default=DEFAULT_BEDROCK_MODEL,
        help=f"Bedrock model ID (default: {DEFAULT_BEDROCK_MODEL})",
    )
    ap.add_argument(
        "--region",
        default=DEFAULT_BEDROCK_REGION,
        help=f"AWS region for Bedrock (default: {DEFAULT_BEDROCK_REGION})",
    )
    ap.add_argument(
        "--workers",
        type=int,
        default=1,
        help="number of concurrent batches to process (1 = serial)",
    )
    args = ap.parse_args()

    entries = load_entries()
    if args.dry_run:
        entries = entries[:100]
        print(f"[dry-run] limiting to {len(entries)} entries")

    print(f"Total entries: {len(entries)}")
    print(f"Batch size: {args.batch}")
    print(f"Backend: {args.backend}")
    if args.backend == "bedrock":
        print(f"Model: {args.model}")
        print(f"Region: {args.region}")

    if not args.merge_only:
        SHARD_DIR.mkdir(parents=True, exist_ok=True)
        # Resume is keyed on food_ids in existing shards, not batch indices —
        # safe to change --batch between runs.
        done_ids = load_done_ids()
        print(f"Already aliased: {len(done_ids)} entries (from existing shards)")

        pending_entries = [e for e in entries if e["id"] not in done_ids]
        print(f"Pending: {len(pending_entries)} entries")
        total_batches = (len(pending_entries) + args.batch - 1) // args.batch
        print(f"Workers: {args.workers} (concurrent batches)")

        # Reserve shard paths up front so each worker has a stable slot.
        batches = []
        for i in range(0, len(pending_entries), args.batch):
            batch = pending_entries[i : i + args.batch]
            shard_path = reserve_shard_path()
            batches.append((batch, shard_path))

        new = 0
        new_lock = threading.Lock()

        def worker(batch, shard_path):
            t0 = time.time()
            try:
                process_batch(
                    batch,
                    shard_path,
                    backend=args.backend,
                    model_id=args.model,
                    region=args.region,
                )
                return True, time.time() - t0, shard_path, None
            except Exception as e:
                # Clean up empty placeholder so re-runs don't see a "done" slot.
                if shard_path.exists() and shard_path.stat().st_size == 0:
                    try:
                        shard_path.unlink()
                    except OSError:
                        pass
                return False, time.time() - t0, shard_path, e

        if args.workers == 1:
            # Serial path — simpler logs.
            for batch, shard_path in batches:
                ok, dt, sp, err = worker(batch, shard_path)
                if ok:
                    new += 1
                    print(
                        f"  batch {new}/{total_batches} ({len(batch)} entries) "
                        f"done in {dt:.1f}s — wrote {sp.name}"
                    )
                else:
                    print(f"  batch ERROR ({sp.name}): {err}")
        else:
            with ThreadPoolExecutor(max_workers=args.workers) as pool:
                futures = [
                    pool.submit(worker, batch, sp) for batch, sp in batches
                ]
                for future in as_completed(futures):
                    ok, dt, sp, err = future.result()
                    with new_lock:
                        if ok:
                            new += 1
                            print(
                                f"  [{new}/{total_batches}] {sp.name} "
                                f"done in {dt:.1f}s",
                                flush=True,
                            )
                        else:
                            print(f"  ERROR ({sp.name}): {err}", flush=True)

        print(f"\nGeneration finished. {new} new shards this run.")

    print("\nMerging shards...")
    merged = merge_shards()
    print(f"Merged: {len(merged)} entries with aliases.")
    validate(merged, [e["id"] for e in entries])

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"Wrote {OUTPUT_PATH.relative_to(ROOT)} ({OUTPUT_PATH.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
