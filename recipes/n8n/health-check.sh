#!/usr/bin/env bash
# health-check.sh — health check for n8n.
# With a URL arg: probes /healthz at that URL directly.
# Without a URL arg (Docker CI mode, run on the target VM): waits for the
# n8n container's Docker healthcheck to report healthy — no published host
# port required.
set -euo pipefail

URL="${1:-}"
CONTAINER_MATCH="n8n-n8n"

if [ -n "$URL" ]; then
  if curl -fsS --max-time 10 "${URL}/healthz" > /dev/null 2>&1; then
    echo "n8n is healthy"
    exit 0
  fi
  echo "n8n health check failed at ${URL}/healthz"
  exit 1
fi

# No URL provided: wait for Docker's own healthcheck to report healthy.
max_wait=300
waited=0
while [ "$waited" -lt "$max_wait" ]; do
  CONTAINER=$(docker ps --filter "name=${CONTAINER_MATCH}" --format '{{.Names}}' 2>/dev/null | head -1)
  if [ -n "$CONTAINER" ]; then
    STATUS=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "healthy" ]; then
      echo "n8n container ${CONTAINER} is healthy after ${waited}s"
      exit 0
    fi
  fi
  echo "  Not ready yet... (${waited}s / ${max_wait}s, status=${STATUS:-none})"
  sleep 5
  waited=$((waited + 5))
done

echo "ERROR: n8n did not become healthy within ${max_wait}s"
echo "--- docker ps -a ---"
docker ps -a 2>&1 || true
echo "--- n8n logs (last 100) ---"
docker logs --tail 100 "$(docker ps -a --filter "name=${CONTAINER_MATCH}" --format '{{.Names}}' | head -1)" 2>&1 || true
exit 1
