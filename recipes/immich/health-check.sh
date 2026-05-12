#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://localhost:2283}"
MAX_WAIT=300
INTERVAL=10
ELAPSED=0

echo "Waiting for Immich at ${URL}/api/server/ping ..."

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -fsS --max-time 5 "${URL}/api/server/ping" > /dev/null 2>&1; then
        echo "Immich is healthy after ${ELAPSED}s"
        exit 0
    fi
    echo "  Not ready yet... (${ELAPSED}s / ${MAX_WAIT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: Immich did not become healthy within ${MAX_WAIT}s"
echo "--- docker ps -a ---"
docker ps -a 2>&1 || true
echo "--- immich-server logs (last 50 lines) ---"
docker logs --tail 50 immich-immich-server-1 2>&1 || true
echo "--- immich-machine-learning logs (last 20 lines) ---"
docker logs --tail 20 immich-immich-machine-learning-1 2>&1 || true
echo "--- postgres logs (last 20 lines) ---"
docker logs --tail 20 immich-postgres-1 2>&1 || true
exit 1
