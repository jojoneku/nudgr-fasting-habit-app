"""
Cross-tier food-parse comparison.

Calls the Lambda (cloud tier) for each test case and prints a results table.
Run from repo root:
    python tools/tier_comparison.py

Requires: boto3, tabulate   (pip install boto3 tabulate)
AWS profile must be active with access to food-coach-handler in ap-southeast-1.
"""

import boto3
import json
import sys
from tabulate import tabulate

FUNCTION = "food-coach-handler"
REGION = "ap-southeast-1"

# ── Test cases ────────────────────────────────────────────────────────────────
# (input_text, ground_truth_kcal, notes)
TEST_CASES = [
    # Gram-explicit — cloud should nail these
    ("100g chicken breast",          165, "USDA: 165 kcal/100g"),
    ("150g fried omelet",            285, "egg+oil ~190 kcal/100g"),
    ("52g banana muffin",            150, "~2.9 kcal/g"),
    ("12g chocolate crinkle",         44, "~3.7 kcal/g cookie"),

    # Piece/count — tests unit conversion
    ("2 boiled eggs",                163, "2 × 57g × 143 kcal/100g"),
    ("1 boiled egg",                  82, "57g × 143 kcal/100g"),
    ("1pc fried chicken wing",       174, "~60g × 290 kcal/100g"),

    # PH chain items — tests portion table
    ("1pc mcdo fried chicken wing part",  319, "110g × 290 kcal/100g"),
    ("jollibee regular french fries",     224, "70g × 320 kcal/100g"),
    ("jollibee chickenjoy 1pc",           312, "120g × 260 kcal/100g"),

    # Volume units
    ("1 cup white rice cooked",      242, "186g × 130 kcal/100g"),
    ("1 scoop whey protein",         120, "30g × 400 kcal/100g"),

    # Tagalog/PH foods
    ("kanin",                        195, "~150g × 130 kcal/100g"),
    ("2 pcs lumpia shanghai",         60, "2 × 30g × 100 kcal/100g"),

    # Composite dishes — cloud should keep as-is or decompose sensibly
    ("chicken adobo 200g",           290, "~145 kcal/100g"),
    ("sinigang na baboy 300g",       198, "~66 kcal/100g broth+pork"),

    # Edge cases
    ("Egg, Whole, Cooked, Scrambled 100g", 155, "USDA canonical — must NOT split"),
    ("kefir milk",                   146, "240g × 61 kcal/100g"),
    ("lechon kawali 100g",           430, "~430 kcal/100g (very fatty)"),
    ("pansit canton with pork and cabbage", 450, "composite dish estimate"),
]

# ── Lambda client ─────────────────────────────────────────────────────────────

lambda_client = boto3.client("lambda", region_name=REGION)

def call_lambda(text: str) -> dict:
    payload = json.dumps({
        "body": json.dumps({
            "op": "parseFoodWithCandidates",
            "payload": {"text": text, "candidates": []},
        })
    })
    resp = lambda_client.invoke(
        FunctionName=FUNCTION,
        InvocationType="RequestResponse",
        Payload=payload.encode(),
    )
    body = json.loads(resp["Payload"].read())
    if body.get("statusCode") != 200:
        return {"error": body}
    return json.loads(body["body"])

# ── Run ───────────────────────────────────────────────────────────────────────

def run():
    rows = []
    errors = []

    for text, gt_kcal, notes in TEST_CASES:
        try:
            result = call_lambda(text)
        except Exception as e:
            errors.append((text, str(e)))
            continue

        items = result.get("items", [])
        intent = result.get("intent", "?")

        if not items:
            rows.append([
                text, f"{gt_kcal}", "—", "—", "—", "—", "❌ no items", notes
            ])
            continue

        total_kcal = 0
        total_g = 0
        sources = set()
        names = []

        for it in items:
            g = it.get("grams", 0)
            total_g += g
            fid = it.get("food_id")
            m = it.get("estimated_macros")
            if fid:
                sources.add("db")
                # DB macros not available without the actual DB lookup from Lambda
                # We only get what the Lambda returns, which is the DB-resolved entry
                # (Lambda doesn't return macros when food_id is set — client fetches from DB)
                # So we flag it and note the food_id
                total_kcal = None  # DB lookup happens client-side
                names.append(f"{it['name']} [DB:{fid[:8]}…]")
            elif m:
                sources.add("est")
                total_kcal = (total_kcal or 0) + m.get("calories", 0)
                names.append(it["name"])
            else:
                sources.add("❓")
                names.append(it["name"])

        kcal_str = f"{total_kcal:.0f}" if total_kcal is not None else "→DB"
        pct_err = ""
        if total_kcal is not None and gt_kcal > 0:
            err = (total_kcal - gt_kcal) / gt_kcal * 100
            pct_err = f"{err:+.0f}%"

        rows.append([
            text,
            str(gt_kcal),
            kcal_str,
            pct_err,
            f"{total_g:.0f}g",
            "/".join(names),
            f"{intent} [{','.join(sources)}]",
            notes,
        ])

    headers = [
        "Input", "GT kcal", "Cloud kcal", "Error",
        "Grams", "Parsed as", "Intent [src]", "Notes"
    ]

    print("\n" + "=" * 120)
    print("CLOUD AI TIER — parseFoodWithCandidates (no DB candidates sent)")
    print("=" * 120)
    print(tabulate(rows, headers=headers, tablefmt="github"))

    if errors:
        print("\nErrors:")
        for text, err in errors:
            print(f"  {text!r}: {err}")

    print("\nNOTE: 'kcal->DB' means cloud picked a DB candidate - actual kcal")
    print("      is fetched client-side from the SQLite DB (not shown here).")
    print("      Check 'Parsed as' for food_id prefix to verify the right item was picked.")

if __name__ == "__main__":
    run()
