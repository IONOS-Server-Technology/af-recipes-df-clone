#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://127.0.0.1:11434}"
MAX_WAIT=120
INTERVAL=5
ELAPSED=0

echo "Waiting for Ollama at ${URL}/api/tags ..."

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -fsS --max-time 5 "${URL}/api/tags" > /dev/null 2>&1; then
        echo "Ollama is healthy after ${ELAPSED}s"
        exit 0
    fi
    echo "  Not ready yet... (${ELAPSED}s / ${MAX_WAIT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: Ollama did not become healthy within ${MAX_WAIT}s"
docker ps -a 2>&1 || true
exit 1
