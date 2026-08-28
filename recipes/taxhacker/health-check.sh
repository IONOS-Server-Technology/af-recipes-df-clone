#!/usr/bin/env bash
# health-check.sh — health check for TaxHacker.
# Without a URL arg (primary path — Docker CI / test-recipes-docker.yaml runs this
# with no arguments on the VM): waits for the taxhacker container's Docker healthcheck
# to report healthy without needing a published host port.
# With a URL arg (manual/secondary path): probes the web UI at that URL directly.
set -euo pipefail

URL="${1:-}"
CONTAINER_MATCH="taxhacker-taxhacker"

if [ -n "$URL" ]; then
    if curl -fsS --max-time 10 "${URL}/" > /dev/null 2>&1; then
        echo "TaxHacker is healthy"
        exit 0
    fi
    echo "TaxHacker health check failed at ${URL}/"
    exit 1
fi

# No URL provided: wait for Docker's own healthcheck to report healthy.
max_wait=300
waited=0
STATUS="unknown"
while [ "$waited" -lt "$max_wait" ]; do
    CONTAINER=$(docker ps --filter "name=${CONTAINER_MATCH}" --format '{{.Names}}' 2>/dev/null | head -1)
    if [ -n "$CONTAINER" ]; then
        STATUS=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null || echo "unknown")
        if [ "$STATUS" = "healthy" ]; then
            echo "TaxHacker container ${CONTAINER} is healthy after ${waited}s"
            exit 0
        fi
    fi
    echo "  Not ready yet... (${waited}s / ${max_wait}s, status=${STATUS})"
    sleep 5
    waited=$((waited + 5))
done

echo "ERROR: TaxHacker did not become healthy within ${max_wait}s"
echo "--- docker ps -a ---"
docker ps -a 2>&1 || true
echo "--- taxhacker logs (last 100) ---"
docker logs --tail 100 "$(docker ps -a --filter "name=${CONTAINER_MATCH}" --format '{{.Names}}' | head -1)" 2>&1 || true
exit 1
