#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://127.0.0.1:3004}"
MAX_WAIT=300
INTERVAL=10
ELAPSED=0

echo "Waiting for Open WebUI at ${URL}/health ..."

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -fsS --max-time 5 "${URL}/health" > /dev/null 2>&1; then
        echo "open-webui is healthy after ${ELAPSED}s"
        exit 0
    fi
    echo "  Not ready yet... (${ELAPSED}s / ${MAX_WAIT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: open-webui did not become healthy within ${MAX_WAIT}s"
echo "--- docker ps -a ---"
docker ps -a 2>&1 || true
echo "--- open-webui container logs (last 100 lines) ---"
docker logs --tail 100 open-webui-open-webui-1 2>&1 || true
echo "--- ollama container logs (last 50 lines) ---"
docker logs --tail 50 open-webui-ollama-1 2>&1 || true
exit 1
