#!/usr/bin/env bash
# health-check.sh — health check for Open WebUI.
# With a URL arg: probes /health at that URL directly.
# Without a URL arg (Docker CI mode, run on the target VM): waits for the
# open-webui container's Docker healthcheck to report healthy — no published
# host port required.
set -euo pipefail

URL="${1:-}"
CONTAINER_MATCH="open-webui-open-webui"

if [ -n "$URL" ]; then
  if curl -fsS --max-time 10 "${URL}/health" > /dev/null 2>&1; then
    echo "Open WebUI is healthy"
    exit 0
  fi
  echo "Open WebUI health check failed at ${URL}/health"
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
      echo "Open WebUI container ${CONTAINER} is healthy after ${waited}s"
      exit 0
    fi
  fi
  echo "  Not ready yet... (${waited}s / ${max_wait}s, status=${STATUS:-none})"
  sleep 5
  waited=$((waited + 5))
done

echo "ERROR: Open WebUI did not become healthy within ${max_wait}s"
echo "--- docker ps -a ---"
docker ps -a 2>&1 || true
echo "--- open-webui logs (last 100) ---"
docker logs --tail 100 "$(docker ps -a --filter "name=${CONTAINER_MATCH}" --format '{{.Names}}' | head -1)" 2>&1 || true
echo "--- ollama logs (last 50) ---"
docker logs --tail 50 "$(docker ps -a --filter 'name=open-webui-ollama' --format '{{.Names}}' | head -1)" 2>&1 || true
exit 1
