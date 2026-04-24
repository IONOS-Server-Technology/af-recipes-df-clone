#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://127.0.0.1:5678}"
MAX_WAIT=120
INTERVAL=10
ELAPSED=0

echo "Waiting for n8n at ${URL}/healthz ..."

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -fsS --max-time 5 "${URL}/healthz" > /dev/null 2>&1; then
        echo "n8n is healthy after ${ELAPSED}s"
        exit 0
    fi
    echo "  Not ready yet... (${ELAPSED}s / ${MAX_WAIT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: n8n did not become healthy within ${MAX_WAIT}s"
exit 1
