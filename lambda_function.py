import json
import os
import re

import boto3


_bedrock = boto3.client("bedrock-runtime", region_name="ap-southeast-1")
_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]


def lambda_handler(event, context):
    print(f"event: {json.dumps(event)}")

    # User ID injected by API Gateway JWT authorizer after token verification.
    user_id = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
        .get("sub")
    )

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
