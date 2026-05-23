import json
import os
import re

import boto3


_bedrock = boto3.client("bedrock-runtime", region_name="ap-southeast-1")
_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]


def lambda_handler(event, context):
    print(f"event: {json.dumps(event)}")

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _resp(400, {"error": "invalid_json", "message": "Body is not valid JSON"})

    op = body.get("op")
    payload = body.get("payload", {})

    if op == "disambiguateFood":
        return _disambiguate_food(payload)
    if op == "extractFoodItems":
        return _extract_food_items(payload)
    if op == "estimateMacros":
        return _estimate_macros(payload)
    if op == "parseFoodWithCandidates":
        return _parse_food_with_candidates(payload)
    if op == "respond":
        return _respond(payload)

    return _resp(400, {"error": "unsupported_op", "message": f"op '{op}' not implemented"})


def _disambiguate_food(payload):
    query = payload.get("query", "").strip()
    candidates = payload.get("candidates", [])

    if not query:
        return _resp(400, {"error": "missing_query", "message": "payload.query is required"})

    if not candidates:
        return _resp(200, {"foodId": None, "confidence": 0.0})

    candidates_text = "\n".join(
        f"- id: {c.get('food_id', c.get('id', '?'))}, name: {c.get('name', '?')}"
        for c in candidates[:5]
    )
    prompt = (
        f'User searched for: "{query}"\n\n'
        f"Candidate foods from the database:\n{candidates_text}\n\n"
        "Pick the best matching candidate. "
        "Reply with ONLY valid JSON, no other text:\n"
        '{"foodId": "<food_id of best match>", "confidence": <0.0 to 1.0>}\n'
        "Set confidence below 0.5 if no candidate is a good match."
    )

    return _invoke_bedrock(
        prompt=prompt,
        max_tokens=128,
        parse_fn=lambda parsed: _resp(200, {
            "foodId": parsed.get("foodId"),
            "confidence": float(parsed.get("confidence", 0.0)),
        }),
        fallback={"foodId": None, "confidence": 0.0},
    )


def _extract_food_items(payload):
    text = payload.get("text", "").strip()
    if not text:
        return _resp(400, {"error": "missing_text"})

    prompt = (
        f'Extract all individual food items from this meal description:\n"{text}"\n\n'
        "For each item reply with ONLY valid JSON, no other text:\n"
        '{"items": [{"name": "<food name>", "grams": <estimated grams as number>, "hyde": "<verbose description for search>"}]}\n'
        "Use 100g as the default portion when quantity is unclear. "
        "hyde should be a descriptive phrase like 'cooked white rice, steamed, plain'."
    )

    return _invoke_bedrock(
        prompt=prompt,
        max_tokens=512,
        parse_fn=lambda parsed: _resp(200, {"items": parsed.get("items", [])}),
        fallback={"items": []},
    )


def _parse_food_with_candidates(payload):
    """Plan 026 — single-call extract + resolve + estimate.

    Takes the raw meal text plus a pre-fetched candidate pool from the
    client's FTS/alias-aware retrieval. Returns each extracted item with
    either:
      - food_id + confidence (when a candidate matches), OR
      - estimated_macros (when no candidate fits; Haiku estimates from
        its own knowledge).
    """
    text = (payload.get("text") or "").strip()
    if not text:
        return _resp(400, {"error": "missing_text"})

    candidates = payload.get("candidates") or []
    if candidates:
        def _expand_slash_variants(name):
            """'Afritada (Pork/Chicken)' → 'also matches: Afritada Pork, Afritada Chicken'"""
            m = re.match(r'^(.+?)\s*\(([^)]+/[^)]+)\)\s*$', name.strip())
            if not m:
                return ""
            base = m.group(1).strip()
            variants = [v.strip() for v in m.group(2).split('/') if v.strip()]
            return "also matches: " + ", ".join(f"{base} {v}" for v in variants)

        def _fmt_candidate(c):
            name = c.get("name", "?")
            cal = c.get("cal_per_100g")
            p = c.get("protein_per_100g")
            f = c.get("fat_per_100g")
            carb = c.get("carbs_per_100g")
            macro = ""
            if cal is not None:
                macro = f" | {cal:.0f} kcal"
                if p is not None and f is not None and carb is not None:
                    macro += f", P{p:.0f} F{f:.0f} C{carb:.0f} /100g"
            slash = _expand_slash_variants(name)
            suffix = f"  [{slash}]" if slash else ""
            return f"- id: {c.get('food_id', c.get('id', '?'))}, name: {name}{macro}{suffix}"

        candidates_text = "\n".join(_fmt_candidate(c) for c in candidates[:15])
        candidates_block = (
            "\n\nCandidate foods from the user's database (pick from these when one matches):\n"
            f"{candidates_text}\n"
        )
    else:
        candidates_block = "\n\nNo candidates provided — estimate macros for every item from your own knowledge.\n"

    prompt = (
        f'Extract all food items from this meal description:\n"{text}"\n'
        f"{candidates_block}\n"
        "For each item, output one object with these fields:\n"
        '  "name": short food name\n'
        '  "grams": estimated portion size in grams (use 100 when unclear)\n'
        '  "hyde": short descriptive phrase for later search (e.g. "cooked white rice, steamed, plain")\n'
        '  "food_id": id of the best candidate match, or null if no candidate fits well\n'
        '  "confidence": 0.0 to 1.0 — your confidence in the food_id pick (ignored when food_id is null)\n'
        '  "estimated_macros": REQUIRED when food_id is null; otherwise null.\n'
        '                       Object: {"calories": number, "protein_g": number, "carbs_g": number, "fat_g": number}\n'
        "\n"
        'At the top level, also set "intent" to one of:\n'
        '  "single_dish" — the user is logging ONE composite dish whose ingredients '
        "happen to be named (connectors like 'with', 'at', 'into'; OR no per-item weights; "
        "OR a single total weight at the start like '150g egg with sardines'). The client "
        "will combine the items into one log entry.\n"
        '  "items_list" — the user is logging SEPARATE items, each with their own portion '
        "(per-item weights like '100g rice and 80g chicken'; commas or 'and' as list separators; "
        "or items that are clearly different courses). The client will log them separately.\n"
        '  When in doubt, prefer "single_dish" only if a connector like "with" / "at" is used '
        "with at most 4 ingredients. Otherwise default to \"items_list\".\n"
        "\n"
        "Rules:\n"
        "1. MATCH — pick food_id only when the candidate describes the same food at the SAME OR MORE "
        "GENERIC level than the user's query. Ask yourself: does the candidate name add any attribute "
        "the user did NOT state (regional origin, preparation style, flavour, brand, texture, sauce)? "
        "If yes, the candidate is too specific — it is NOT a match, even if it shares keywords. "
        "Examples of WRONG picks: 'fried chicken'→'Korean fried chicken'; "
        "'white rice'→'Japanese short-grain rice'; 'pork'→'BBQ pork ribs'; "
        "'bread'→'Garlic butter toast'. When no sufficiently generic candidate exists, "
        "set food_id to null.\n"
        "2. CONFIDENCE — reflects name-level fit, not macro certainty. Exact or generic match ≥ 0.85. "
        "One minor extra word that doesn't change the dish identity (e.g. 'steamed' vs. 'plain') "
        "0.70–0.84. Any qualifier that CHANGES the dish (regional origin, brand, sauce, cooking style "
        "the user didn't mention): set food_id to null — do not just lower confidence.\n"
        "3. ESTIMATION — when food_id is null, estimate macros from your knowledge AND use any "
        "nutritionally similar candidates in the list as an anchor. If a candidate shares the main "
        "ingredient and cooking method (e.g. 'Chicken, fried | 245 kcal, P28 F14 C0 /100g'), anchor "
        "your estimate near those values rather than guessing freely.\n"
        "4. MACROS — output per the whole item portion (grams), not per 100g. "
        "Multiply candidate /100g values by (grams/100) before using as anchor.\n"
        "5. PRECISION — round to one decimal place.\n"
        "\n"
        "Reply with ONLY valid JSON, no markdown, no commentary:\n"
        '{"intent": "single_dish" | "items_list", "items": [...]}\n'
    )

    return _invoke_bedrock(
        prompt=prompt,
        max_tokens=1024,
        parse_fn=lambda parsed: _emit_parse_food_response(parsed),
        fallback={"intent": "items_list", "items": []},
    )


def _emit_parse_food_response(parsed):
    normalized = _normalize_parsed_items(parsed)
    items = normalized.get("items", [])
    resolved = sum(1 for i in items if i.get("food_id"))
    estimated = sum(1 for i in items if i.get("estimated_macros"))
    intent = normalized.get("intent", "items_list")
    # Structured cost-monitoring log line — picked up by CloudWatch Insights.
    print(
        f"cost_line op=parseFoodWithCandidates items={len(items)} "
        f"resolved={resolved} estimated={estimated} intent={intent}"
    )
    return _resp(200, normalized)


def _normalize_parsed_items(parsed):
    """Coerce the model output into the response schema with safe defaults."""
    intent = parsed.get("intent")
    if intent not in ("single_dish", "items_list"):
        intent = "items_list"  # safe default
    items_in = parsed.get("items") or []
    items_out = []
    for it in items_in:
        if not isinstance(it, dict):
            continue
        name = (it.get("name") or "").strip()
        if not name:
            continue
        try:
            grams = float(it.get("grams") or 100)
        except (TypeError, ValueError):
            grams = 100.0
        food_id = it.get("food_id")
        if food_id in ("", "null", None):
            food_id = None
        else:
            # Haiku sometimes returns numeric ids when the source ids look
            # numeric; the Dart side expects a string. Coerce defensively.
            food_id = str(food_id)
        try:
            confidence = float(it.get("confidence") or 0.0)
        except (TypeError, ValueError):
            confidence = 0.0
        macros = it.get("estimated_macros")
        if macros is not None and isinstance(macros, dict):
            macros = {
                "calories": float(macros.get("calories") or 0),
                "protein_g": float(macros.get("protein_g") or 0),
                "carbs_g": float(macros.get("carbs_g") or 0),
                "fat_g": float(macros.get("fat_g") or 0),
            }
        else:
            macros = None
        items_out.append({
            "name": name,
            "grams": grams,
            "hyde": (it.get("hyde") or name).strip(),
            "food_id": food_id,
            "confidence": confidence,
            "estimated_macros": macros,
        })
    return {"intent": intent, "items": items_out}


def _estimate_macros(payload):
    description = payload.get("description", "").strip()
    if not description:
        return _resp(400, {"error": "missing_description"})

    prompt = (
        f'Estimate the macronutrients for this meal:\n"{description}"\n\n'
        "Reply with ONLY valid JSON, no other text:\n"
        '{"calories": <number>, "protein_g": <number>, "carbs_g": <number>, "fat_g": <number>}\n'
        "Use standard nutritional values. Round to one decimal place."
    )

    return _invoke_bedrock(
        prompt=prompt,
        max_tokens=128,
        parse_fn=lambda parsed: _resp(200, {
            "calories": float(parsed.get("calories", 0)),
            "protein_g": float(parsed.get("protein_g", 0)),
            "carbs_g": float(parsed.get("carbs_g", 0)),
            "fat_g": float(parsed.get("fat_g", 0)),
        }),
        fallback={"calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0},
    )


def _respond(payload):
    messages = payload.get("messages", [])
    ctx = payload.get("context", {})

    if not messages:
        return _resp(400, {"error": "missing_messages"})

    # Build system prompt from context
    system_lines = ["You are an AI coach for an intermittent fasting app with an RPG theme (Solo Leveling aesthetic)."]
    if ctx.get("isFasting"):
        elapsed = ctx.get("elapsedFastMinutes", 0)
        goal = ctx.get("fastingGoalHours", 16)
        system_lines.append(f"The user is currently fasting: {elapsed // 60}h {elapsed % 60}m elapsed of {goal}h goal.")
    else:
        system_lines.append("The user is not currently fasting.")
    if ctx.get("fastingStreak"):
        system_lines.append(f"Fasting streak: {ctx['fastingStreak']} days.")
    if ctx.get("playerLevel"):
        system_lines.append(f"Player: Level {ctx['playerLevel']}, {ctx.get('playerXp', 0)} XP, {ctx.get('playerHp', 100)} HP.")
    if ctx.get("todayCalories") is not None:
        system_lines.append(
            f"Today's intake: {ctx['todayCalories']} kcal"
            + (f" / {ctx['calorieGoal']} kcal goal" if ctx.get("calorieGoal") else "")
            + f", protein {ctx.get('todayProtein', 0)}g, carbs {ctx.get('todayCarbs', 0)}g, fat {ctx.get('todayFat', 0)}g."
        )
    system_lines.append("Keep responses concise (2-3 sentences). Be encouraging and use light RPG language.")
    system_prompt = " ".join(system_lines)

    bedrock_messages = [
        {"role": m["role"], "content": m.get("text", "")}
        for m in messages
        if m.get("text", "").strip()
    ]

    try:
        raw = _bedrock.invoke_model(
            modelId=_MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 512,
                "system": system_prompt,
                "messages": bedrock_messages,
            }),
        )
        result = json.loads(raw["body"].read())
        response_text = result["content"][0]["text"].strip()
        return _resp(200, {"response": response_text})
    except Exception as e:
        print(f"Bedrock error (respond): {e}")
        return _resp(502, {"error": "bedrock_error", "message": str(e)})


def _invoke_bedrock(*, prompt, max_tokens, parse_fn, fallback):
    """Shared Bedrock invocation with JSON fence stripping and error handling."""
    try:
        raw = _bedrock.invoke_model(
            modelId=_MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": max_tokens,
                "messages": [{"role": "user", "content": prompt}],
            }),
        )
        result = json.loads(raw["body"].read())
        text = result["content"][0]["text"].strip()
        text = re.sub(r"^```[a-zA-Z]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text).strip()
        parsed = json.loads(text)
        return parse_fn(parsed)
    except json.JSONDecodeError as e:
        print(f"Bedrock response not valid JSON: {e}")
        return _resp(200, fallback)
    except Exception as e:
        print(f"Bedrock error: {e}")
        return _resp(502, {"error": "bedrock_error", "message": str(e)})


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }
