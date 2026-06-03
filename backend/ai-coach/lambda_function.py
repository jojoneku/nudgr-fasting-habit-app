import json
import os
import re
import urllib.request

import boto3

# ── Module-level clients/config (reused across warm invocations) ───────────────

_bedrock = boto3.client("bedrock-runtime", region_name="ap-southeast-1")

_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
_DAILY_CAP = int(os.environ.get("DAILY_CAP", "100"))
_SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
_SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "")
_MAX_TEXT_LEN = 500   # chars; guards prompt-size and injection blast radius
_MAX_CANDIDATES = 15


# ── Auth ───────────────────────────────────────────────────────────────────────

def _get_user_id(event):
    """Extract `sub` from API Gateway HTTP API JWT authorizer claims.

    API GW populates event['requestContext']['authorizer']['jwt']['claims']
    after a successful JWT authorizer check. Returns None if the authorizer
    didn't run (i.e. the request reached Lambda unauthenticated — shouldn't
    happen in production but guards against mis-configured deployments).
    """
    try:
        return event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"]
    except (KeyError, TypeError):
        return None


def _get_bearer_token(event):
    """Return the raw Bearer token from the Authorization header, or ''.

    API Gateway HTTP API lowercases header names; fall back to the capitalised
    form defensively.
    """
    headers = event.get("headers") or {}
    auth = headers.get("authorization") or headers.get("Authorization") or ""
    if auth.lower().startswith("bearer "):
        return auth[7:].strip()
    return ""


# ── Rate limiting ──────────────────────────────────────────────────────────────

def _check_rate_limit(token):
    """Atomically increment the caller's daily counter; return (allowed, count).

    Calls the Supabase `increment_ai_usage` RPC over HTTPS (PostgREST),
    forwarding the user's Bearer token. The SECURITY DEFINER function derives
    the user from auth.uid(), so a caller can only ever bump their own counter.

    Fails open (returns True) on transport/Supabase errors or when rate
    limiting isn't configured, so a transient infra issue never bricks the app.
    """
    if not _SUPABASE_URL or not _SUPABASE_ANON_KEY or not token:
        return True, 0  # not configured / no token → fail open
    req = urllib.request.Request(
        f"{_SUPABASE_URL}/rest/v1/rpc/increment_ai_usage",
        data=b"{}",
        method="POST",
        headers={
            "Content-Type": "application/json",
            "apikey": _SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {token}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            count = int(json.loads(resp.read()))
            return count <= _DAILY_CAP, count
    except Exception as e:
        print(f"Rate limit RPC error: {e}")
        return True, 0  # fail open


# ── Entry point ────────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    print(f"event: {json.dumps(event)}")

    # Auth: API GW JWT authorizer must have verified the Supabase Bearer token.
    # If user_id is None the authorizer did not run — reject defensively.
    user_id = _get_user_id(event)
    if not user_id:
        return _resp(401, {"error": "unauthorized", "message": "Valid Bearer token required"})

    # Per-user daily cap — prevents unbounded Bedrock billing.
    allowed, count = _check_rate_limit(_get_bearer_token(event))
    if not allowed:
        print(f"rate_limit_hit user={user_id} count={count} cap={_DAILY_CAP}")
        return _resp(429, {
            "error": "rate_limit_exceeded",
            "message": f"Daily limit of {_DAILY_CAP} AI requests reached. Try again tomorrow.",
        })

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


# ── Food ops ───────────────────────────────────────────────────────────────────

def _disambiguate_food(payload):
    query = payload.get("query", "").strip()[:_MAX_TEXT_LEN]
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
    text = payload.get("text", "").strip()[:_MAX_TEXT_LEN]
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
    """Single-call extract + resolve + estimate (Plan 026).

    Takes the raw meal text plus a pre-fetched candidate pool from the
    client's FTS/alias-aware retrieval. Returns each extracted item with
    either:
      - food_id + confidence (when a candidate matches), OR
      - estimated_macros (when no candidate fits; Haiku estimates from
        its own knowledge), plus macro_fallback=true when the estimate was
        synthesised from a generic ratio rather than model output.
    """
    text = (payload.get("text") or "").strip()[:_MAX_TEXT_LEN]
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

        candidates_text = "\n".join(_fmt_candidate(c) for c in candidates[:_MAX_CANDIDATES])
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
        "3. ESTIMATION — when food_id is null, you MUST include estimated_macros. Never omit it. "
        "Estimate from your knowledge AND anchor on any nutritionally similar candidate in the list. "
        "If a candidate shares the main ingredient and cooking method "
        "(e.g. 'Chicken, fried | 245 kcal, P28 F14 C0 /100g'), anchor near those values. "
        "Sanity: calories ≈ protein_g×4 + carbs_g×4 + fat_g×9.\n"
        "4. MACROS — output per the whole item portion (grams stated), not per 100g. "
        "Multiply candidate /100g values by (grams/100) before using as anchor.\n"
        "5. GRAMS — If the user stated an explicit weight for a single item "
        "(e.g. '52g banana muffin', '12g chocolate crinkle', '150g fried omelet'), "
        "use EXACTLY that number — do NOT substitute a standard serving size.\n"
        "   Philippine fast-food piece sizes when user says '1pc' or 'regular':\n"
        "   Jollibee Chickenjoy 1pc=120g; Jollibee reg fries=70g, large=117g; "
        "   Jollibee sundae reg=100g, large=140g; Jollibee Burger Steak=230g;\n"
        "   McDonald's fried chicken 1pc (wing part)=110g; McSpicy=180g; "
        "   McDo small fries=70g, medium=117g, large=154g;\n"
        "   KFC Original 1pc=130g; Burger patty 1pc=75g.\n"
        "   Default serving sizes when no amount is stated:\n"
        "   Kanin / cooked rice (plain, no modifier): 150g; "
        "   Boiled or fried egg (1 egg, no stated weight): 60g; "
        "   Lumpia shanghai (1 piece): 30g; "
        "   Liquid/drink (milk, kefir, juice, shake, 1 glass/cup): 240g; "
        "   Pansit / noodle dish (1 serving): 200g.\n"
        "6. CANONICAL NAMES — USDA-style names like 'Egg, Whole, Cooked, Scrambled' or "
        "'Beef, Ground, 80% Lean' are ONE single ingredient (comma = modifier, not separator). "
        "Do NOT decompose them into multiple items.\n"
        "7. PRECISION — round to one decimal place.\n"
        "\n"
        "Reply with ONLY valid JSON, no markdown, no commentary:\n"
        '{"intent": "single_dish" | "items_list", "items": [...]}\n'
    )

    return _invoke_bedrock(
        prompt=prompt,
        max_tokens=1024,
        parse_fn=lambda parsed: _emit_parse_food_response(parsed, original_text=text),
        fallback={"intent": "items_list", "items": []},
    )


def _emit_parse_food_response(parsed, original_text=""):
    normalized = _normalize_parsed_items(parsed, original_text=original_text)
    items = normalized.get("items", [])
    resolved = sum(1 for i in items if i.get("food_id"))
    estimated = sum(1 for i in items if i.get("estimated_macros"))
    fallback = sum(1 for i in items if i.get("macro_fallback"))
    intent = normalized.get("intent", "items_list")
    print(
        f"cost_line op=parseFoodWithCandidates items={len(items)} "
        f"resolved={resolved} estimated={estimated} macro_fallback={fallback} intent={intent}"
    )
    return _resp(200, normalized)


def _extract_single_explicit_grams(text):
    """Return the single explicit gram count in text, or None if there are 0 or 2+ matches."""
    matches = re.findall(r'(\d+(?:\.\d+)?)\s*(?:g|gm|gms|gram|grams)\b', text, re.IGNORECASE)
    if len(matches) == 1:
        try:
            return float(matches[0])
        except ValueError:
            return None
    return None


_MAX_CAL_PER_ITEM = 3000.0   # sanity ceiling for a single logged portion
_MAX_MACRO_G = 500.0          # sanity ceiling for a single macro in grams


def _clamp_macros(macros):
    """Clamp estimated macro values to nutritionally plausible ranges."""
    if macros is None:
        return None
    return {
        "calories": max(0.0, min(float(macros.get("calories", 0)), _MAX_CAL_PER_ITEM)),
        "protein_g": max(0.0, min(float(macros.get("protein_g", 0)), _MAX_MACRO_G)),
        "carbs_g": max(0.0, min(float(macros.get("carbs_g", 0)), _MAX_MACRO_G)),
        "fat_g": max(0.0, min(float(macros.get("fat_g", 0)), _MAX_MACRO_G)),
    }


def _normalize_parsed_items(parsed, original_text=""):
    """Coerce the model output into the response schema with safe defaults."""
    intent = parsed.get("intent")
    if intent not in ("single_dish", "items_list"):
        intent = "items_list"
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
            # Haiku sometimes returns numeric ids; the Dart side expects a string.
            food_id = str(food_id)
        try:
            confidence = float(it.get("confidence") or 0.0)
        except (TypeError, ValueError):
            confidence = 0.0
        macros = it.get("estimated_macros")
        macro_fallback = False
        if macros is not None and isinstance(macros, dict):
            macros = _clamp_macros({
                "calories": float(macros.get("calories") or 0),
                "protein_g": float(macros.get("protein_g") or 0),
                "carbs_g": float(macros.get("carbs_g") or 0),
                "fat_g": float(macros.get("fat_g") or 0),
            })
        else:
            macros = None
        # Safety net: model forgot estimated_macros despite prompt instruction.
        # Synthesise a rough ~2 kcal/g estimate and set macro_fallback so the
        # client can warn the user that this figure is approximate.
        if food_id is None and macros is None:
            kcal = round(grams * 2.0, 1)
            macros = {
                "calories": kcal,
                "protein_g": round(kcal * 0.15 / 4, 1),
                "carbs_g": round(kcal * 0.50 / 4, 1),
                "fat_g": round(kcal * 0.35 / 9, 1),
            }
            macro_fallback = True
        items_out.append({
            "name": name,
            "grams": grams,
            "hyde": (it.get("hyde") or name).strip(),
            "food_id": food_id,
            "confidence": confidence,
            "estimated_macros": macros,
            "macro_fallback": macro_fallback,
        })

    # Single-item explicit-gram override: user wrote "12g crinkle" but model
    # returned 40g. Trust the user's stated weight.
    if len(items_out) == 1 and original_text:
        user_grams = _extract_single_explicit_grams(original_text)
        if user_grams and user_grams > 0:
            item = items_out[0]
            if abs(item["grams"] - user_grams) / user_grams > 0.05:
                if item["estimated_macros"] and item["grams"] > 0:
                    ratio = user_grams / item["grams"]
                    m = item["estimated_macros"]
                    item["estimated_macros"] = {
                        "calories": round(m["calories"] * ratio, 1),
                        "protein_g": round(m["protein_g"] * ratio, 1),
                        "carbs_g": round(m["carbs_g"] * ratio, 1),
                        "fat_g": round(m["fat_g"] * ratio, 1),
                    }
                item["grams"] = user_grams

    return {"intent": intent, "items": items_out}


def _estimate_macros(payload):
    description = payload.get("description", "").strip()[:_MAX_TEXT_LEN]
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


# ── Chat / respond ─────────────────────────────────────────────────────────────

def _enforce_alternation(messages):
    """Coalesce consecutive same-role turns; drop leading assistant messages.

    Bedrock rejects message lists that start with 'assistant' or contain
    two consecutive turns of the same role (ValidationException → 502).
    """
    if not messages:
        return []
    # Drop any leading assistant messages.
    while messages and messages[0]["role"] == "assistant":
        messages.pop(0)
    if not messages:
        return []
    # Coalesce consecutive same-role turns by joining their content.
    result = [dict(messages[0])]
    for msg in messages[1:]:
        if msg["role"] == result[-1]["role"]:
            result[-1]["content"] += "\n" + msg["content"]
        else:
            result.append(dict(msg))
    return result


def _respond(payload):
    messages = payload.get("messages", [])
    ctx = payload.get("context", {})

    if not messages:
        return _resp(400, {"error": "missing_messages"})

    system_lines = [
        "You are an AI coach for an intermittent fasting app with an RPG theme (Solo Leveling aesthetic).",
        # Safety guardrail — must come early so later context doesn't override it.
        "Important: never provide specific medical advice, diagnoses, medication dosages, "
        "or treatment recommendations. For any medical concern, always refer the user to a "
        "qualified healthcare professional.",
    ]
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

    raw_messages = [
        {"role": m["role"], "content": m.get("text", "")}
        for m in messages
        if m.get("text", "").strip()
    ]
    bedrock_messages = _enforce_alternation(raw_messages)

    if not bedrock_messages:
        return _resp(400, {"error": "missing_messages", "message": "No valid user messages after filtering"})

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


# ── Shared Bedrock helper ──────────────────────────────────────────────────────

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
