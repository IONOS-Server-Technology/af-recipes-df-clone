#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://${SERVERIP:-127.0.0.1}:3001}"
MAX_WAIT=180
INTERVAL=10
ELAPSED=0

echo "Waiting for Uptime Kuma at ${URL}/api/entry-page ..."

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -fsS --max-time 5 "${URL}/api/entry-page" > /dev/null 2>&1; then
        echo "Uptime Kuma is healthy after ${ELAPSED}s"
        exit 0
    fi
    echo "  Not ready yet... (${ELAPSED}s / ${MAX_WAIT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: Uptime Kuma did not become healthy within ${MAX_WAIT}s"
exit 1
