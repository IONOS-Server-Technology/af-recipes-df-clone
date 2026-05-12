#!/usr/bin/env bash
set -euo pipefail

URL="${1:-https://127.0.0.1:9443}"
MAX_WAIT=120
INTERVAL=5
ELAPSED=0

echo "Waiting for Portainer at ${URL}/api/status ..."

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -fsSk --max-time 5 "${URL}/api/status" > /dev/null 2>&1; then
        echo "Portainer is healthy after ${ELAPSED}s"
        exit 0
    fi
    echo "  Not ready yet... (${ELAPSED}s / ${MAX_WAIT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: Portainer did not become healthy within ${MAX_WAIT}s"
docker ps -a 2>&1 || true
exit 1
