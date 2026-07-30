#!/usr/bin/env bash
# Build the Treasury web companion, then install the service-worker retirement
# script over the empty file Flutter leaves behind.
#
# Use this instead of a bare `flutter build web`. A build that skips the copy
# below ships a 0-byte /flutter_service_worker.js, which leaves every browser
# that already registered a worker stuck serving its cached bundle — the exact
# failure this is here to end.
#
# Usage: scripts/build_web.sh [extra flutter build web args...]
#   e.g. scripts/build_web.sh --dart-define=AI_COACH_ENDPOINT=https://…
set -euo pipefail

# --pwa-strategy=none: no service worker. Flutter's worker serves the PREVIOUS
# bundle while it installs the new one, so the new code only activates on the
# *next* navigation — every deploy took two loads to appear and read as "the
# deploy didn't land". An authenticated dashboard gains nothing from offline
# caching.
flutter build web --release -t lib/main_web.dart --pwa-strategy=none "$@"

# The flag stops Flutter REGISTERING a worker for new visitors (the generated
# flutter_bootstrap.js calls `_flutter.loader.load()` with no
# serviceWorkerSettings), but it still writes flutter_service_worker.js as a
# 0-byte file. Browsers holding an existing registration poll that exact path
# for an update, so it has to carry the retirement script or they never heal.
# firebase.json serves the path `no-cache` so the poll is never answered from
# cache.
cp scripts/web/retire_service_worker.js build/web/flutter_service_worker.js

# Fail loudly rather than shipping a build that cannot retire old workers —
# a future Flutter could start overwriting the file after this copy.
if ! grep -q 'registration.unregister' build/web/flutter_service_worker.js; then
  echo "::error file=scripts/web/retire_service_worker.js::build/web/flutter_service_worker.js is not the retirement script; Flutter overwrote it after the copy."
  exit 1
fi

echo "Built build/web with the service-worker retirement script installed."
