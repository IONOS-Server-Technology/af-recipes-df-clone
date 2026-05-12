#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:2283}"
echo "Checking Immich at ${URL}/api/server/ping ..."
curl -fsS --max-time 10 "${URL}/api/server/ping" > /dev/null
echo "Immich is healthy."
