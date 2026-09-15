#!/usr/bin/env bash
# Asserts that the two production AI front doors still refuse anonymous callers.
#
# Why this exists, and why it reads the LIVE resources:
#
# backend/ai-coach/template.yaml declares the Supabase JWT authorizer, but that
# template provisions `ai-coach`/`ai-coach-api` while production runs
# `food-coach-handler` behind `food-coach-api` (the file says so at the top).
# CI only pushes function CODE. So the authorizer standing between the open
# internet and a Bedrock bill exists ONLY as a setting somebody applied in the
# console, with no IaC behind it and — until this script — nothing asserting it.
# The next person who recreates that API is exactly who forgets it.
#
# The Lambda itself fails closed (`_get_user_id` returns None with no authorizer
# claims, and the handler 401s), so losing the authorizer breaks the endpoint
# rather than opening it. That is the good failure mode, not a reason to skip
# the check: a silently dead coach API is still an outage, and the fail-closed
# guard is one refactor away from being "simplified" out.
#
# scripts/check_api_cors.sh is the sibling that asserts browsers can reach it.
# Same conventions here: exit 0 = fine (or not checkable), exit 1 = misconfigured.
set -uo pipefail

API_NAME="${API_NAME:-food-coach-api}"
ROUTE_KEY="${ROUTE_KEY:-POST /v1/coach}"
ADVISOR_FUNCTION="${ADVISOR_FUNCTION:-food-advisor-stream}"

fail=0

# ── 1. The HTTP API in front of food-coach-handler ────────────────────────────

API_ID=$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" \
  --output text 2>/dev/null || echo "")

if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
  # Same two benign causes as the CORS check: missing apigatewayv2:GetApis on
  # the deploy credentials, or the CLI defaulting to a region that is not
  # ap-southeast-1. Neither is evidence of a missing authorizer, so warn.
  echo "::warning::Could not resolve the '${API_NAME}' API id in region '${AWS_REGION:-default}'; skipping the authorizer check. Needs apigatewayv2:GetApis, and the right region."
else
  AUTHORIZERS=$(aws apigatewayv2 get-authorizers --api-id "$API_ID" \
    --query 'Items[].{Id:AuthorizerId,Type:AuthorizerType,Issuer:JwtConfiguration.Issuer,Audience:JwtConfiguration.Audience}' \
    --output json 2>/dev/null || echo "null")
  ROUTES=$(aws apigatewayv2 get-routes --api-id "$API_ID" \
    --query 'Items[].{Key:RouteKey,AuthType:AuthorizationType,AuthorizerId:AuthorizerId}' \
    --output json 2>/dev/null || echo "null")

  AUTHORIZERS="$AUTHORIZERS" ROUTES="$ROUTES" ROUTE_KEY="$ROUTE_KEY" python3 <<'PYEOF'
import json
import os
import sys


def load(name):
    raw = (os.environ.get(name) or "").strip()
    try:
        return json.loads(raw) if raw else None
    except json.JSONDecodeError:
        return None


authorizers = load("AUTHORIZERS") or []
routes = load("ROUTES") or []
route_key = os.environ["ROUTE_KEY"]

FIX = "\n".join([
    "Re-attach a Supabase JWT authorizer to the live API. The shape is in",
    "backend/ai-coach/template.yaml (SupabaseJWT). Note the template CANNOT be",
    "deployed over production as-is — it names different resources — so apply it",
    "to the live API, then re-run this check.",
    "",
    "The issuer MUST be https://<project-ref>.supabase.co/auth/v1 and the",
    "Supabase project's JWT signing key MUST be RSA. API Gateway's native JWT",
    "authorizer cannot validate ES256, and an ECC key 401s every valid token.",
])

problems = []

jwt_authorizers = [a for a in authorizers if (a.get("Type") or "").upper() == "JWT"]
if not jwt_authorizers:
    problems.append(
        "the API has NO JWT authorizer, so nothing verifies the caller's "
        "Supabase token at the edge"
    )

for a in jwt_authorizers:
    issuer = a.get("Issuer") or ""
    if not issuer.startswith("https://") or not issuer.endswith("/auth/v1"):
        problems.append(
            "authorizer %s has issuer %r, expected https://<ref>.supabase.co/auth/v1"
            % (a.get("Id"), issuer)
        )
    audience = [str(x) for x in (a.get("Audience") or [])]
    if "authenticated" not in audience:
        problems.append(
            "authorizer %s audience is %r, expected it to include 'authenticated'"
            % (a.get("Id"), audience)
        )

# An authorizer that exists but is not bound to the route protects nothing.
match = next((r for r in routes if r.get("Key") == route_key), None)
if match is None:
    keys = sorted(str(r.get("Key")) for r in routes)
    problems.append(
        "route %r not found on this API (routes present: %s)" % (route_key, keys)
    )
else:
    if (match.get("AuthType") or "NONE").upper() != "JWT":
        problems.append(
            "route %r has AuthorizationType %r, expected 'JWT' — the route is "
            "reachable without a token" % (route_key, match.get("AuthType"))
        )
    if not match.get("AuthorizerId"):
        problems.append(
            "route %r has no AuthorizerId, so no authorizer runs for it" % route_key
        )

if problems:
    print("::error::Coach API auth is misconfigured: " + "; ".join(problems) + "\n" + FIX)
    sys.exit(1)

print("Coach API: JWT authorizer present and bound to %s." % route_key)
PYEOF
  [ $? -ne 0 ] && fail=1
fi

# ── 2. The advisor's Lambda Function URL ──────────────────────────────────────
#
# This one must stay AWS_IAM. CloudFront reaches it with an OAC-signed SigV4
# request; flipping it to NONE would publish the function's own URL to the
# internet, bypassing the distribution. app.py verifies the Supabase token
# itself so it would still refuse anonymous callers, but it would put an
# unmetered, directly-addressable Bedrock front door online — and the README's
# "nothing is publicly invokable" would quietly stop being true.

URL_AUTH=$(aws lambda get-function-url-config \
  --function-name "$ADVISOR_FUNCTION" \
  --query 'AuthType' --output text 2>/dev/null || echo "")

if [ -z "$URL_AUTH" ] || [ "$URL_AUTH" = "None" ]; then
  echo "::warning::Could not read the Function URL config for '${ADVISOR_FUNCTION}'; skipping. Needs lambda:GetFunctionUrlConfig, and the right region."
elif [ "$URL_AUTH" != "AWS_IAM" ]; then
  echo "::error::${ADVISOR_FUNCTION}'s Function URL AuthType is '${URL_AUTH}', expected 'AWS_IAM'. Anything but AWS_IAM makes the Function URL directly invokable from the internet, around CloudFront. Fix with:
  aws lambda update-function-url-config --function-name ${ADVISOR_FUNCTION} --auth-type AWS_IAM"
  fail=1
else
  echo "Advisor Function URL: AuthType AWS_IAM (reachable only via CloudFront OAC)."
fi

exit $fail
