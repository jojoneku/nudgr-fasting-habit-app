#!/usr/bin/env bash
# Asserts that the production AI-coach HTTP API allows browser calls.
#
# The web build calls this endpoint from a browser, and a request carrying
# Authorization + Content-Type is not a "simple" request: the browser sends a
# preflight OPTIONS first, and an API that does not answer it makes every call
# fail at the transport layer. From Dart that is indistinguishable from being
# offline, so it surfaced as "Advisor unreachable. Check your connection" on a
# perfectly good connection — and took Money Mentor and the chat logger's
# category classification down with it, since both go through this endpoint.
#
# backend/ai-coach/template.yaml declares CorsConfiguration, but that template
# provisions `ai-coach`/`ai-coach-api` while production runs
# `food-coach-handler` behind `food-coach-api`. CI only pushes function CODE, so
# the template's CORS block has never applied to production. Hence this check
# reads the LIVE API rather than trusting the template.
#
# Exit codes: 0 = fine (or not checkable), 1 = misconfigured.
set -uo pipefail

API_NAME="${API_NAME:-food-coach-api}"

API_ID=$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" \
  --output text 2>/dev/null || echo "")

if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
  # Read access is not guaranteed by the deploy credentials, and a missing
  # permission is not evidence of a missing config — warn, never fail.
  echo "::warning::Could not resolve the '${API_NAME}' API id; skipping the CORS check. Grant apigatewayv2:GetApis to enable it."
  exit 0
fi

CORS=$(aws apigatewayv2 get-api --api-id "$API_ID" \
  --query 'CorsConfiguration' --output json 2>/dev/null || echo "null")
echo "CorsConfiguration: $CORS"

CORS="$CORS" python3 <<'PYEOF'
import json
import os
import sys

raw = os.environ.get("CORS", "").strip()
try:
    cfg = json.loads(raw) if raw else None
except json.JSONDecodeError:
    cfg = None

FIX = (
    "  aws apigatewayv2 update-api --api-id <id> --cors-configuration "
    'AllowOrigins="https://nudgr-app.web.app",'
    'AllowHeaders="content-type,authorization",'
    'AllowMethods="POST,OPTIONS"'
)

if not cfg:
    print(
        "::error::The API has NO CorsConfiguration. Browser calls fail at the "
        "preflight, so the web app reports the advisor as unreachable and chat "
        "logging cannot classify a category. Fix with:\n" + FIX
    )
    sys.exit(1)


def lowered(values):
    return {str(v).lower() for v in (values or [])}


headers = lowered(cfg.get("AllowHeaders"))
methods = lowered(cfg.get("AllowMethods"))
origins = lowered(cfg.get("AllowOrigins"))

problems = []
# Authorization has to be allowed BY NAME: a wildcard does not cover it once the
# request is authenticated, and every call to this endpoint carries a bearer
# token. Content-Type matters because the body is JSON.
for header in ("authorization", "content-type"):
    if header not in headers and "*" not in headers:
        problems.append("AllowHeaders is missing %r" % header)
if "post" not in methods and "*" not in methods:
    problems.append("AllowMethods is missing 'POST'")
if not origins:
    problems.append("AllowOrigins is empty")

if problems:
    print("::error::CORS is incomplete: " + "; ".join(problems) + "\n" + FIX)
    sys.exit(1)

print("CORS allows browser calls.")
PYEOF
