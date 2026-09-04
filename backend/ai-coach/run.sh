#!/bin/bash
# Entrypoint for the STREAMING advisor only, run by the Lambda Web Adapter.
#
# The adapter (attached as a layer, with AWS_LAMBDA_EXEC_WRAPPER=/opt/bootstrap)
# translates each invocation into an HTTP request against this server and
# streams the response back out. Lambda cannot stream from the Python managed
# runtime directly, which is the whole reason this file exists.
#
# --no-access-log because CloudWatch already has the cost_line, and an access
# line per request would double the log volume to say less.
exec python -m uvicorn app:app --host 0.0.0.0 --port "${PORT:-8080}" --no-access-log
