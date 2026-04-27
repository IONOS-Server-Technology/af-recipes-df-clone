#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://127.0.0.1:5678}"
MAX_WAIT=300
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
echo "--- docker ps -a ---"
docker ps -a 2>/dev/null || true
echo "--- n8n container logs (last 50 lines) ---"
docker logs --tail 50 n8n-n8n-1 2>/dev/null || true
exit 1
