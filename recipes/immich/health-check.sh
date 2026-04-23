#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://127.0.0.1:2283}"
echo "Checking Immich at ${URL}/api/server-info/ping ..."
curl -fsS --max-time 10 "${URL}/api/server-info/ping" > /dev/null
echo "Immich is healthy."
