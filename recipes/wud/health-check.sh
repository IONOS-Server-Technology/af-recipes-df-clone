#!/usr/bin/env bash
# health-check.sh — CI-only health check for WUD
# Accepts HTTP 200 (unauthenticated) and 401 (auth enabled) as healthy.
# With URL arg: probes the given endpoint directly.
# Without URL arg (Docker CI mode): checks container health via docker inspect.
set -euo pipefail

URL="${1:-}"

if [ -n "$URL" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${URL}/api/registries")
  if echo "$HTTP_CODE" | grep -qE '^(200|401)$'; then
    echo "WUD is healthy (HTTP ${HTTP_CODE})"
    exit 0
  fi
  echo "WUD health check failed (HTTP ${HTTP_CODE})"
  exit 1
fi

# No URL provided: wait for Docker's own healthcheck to report healthy.
# WUD has no published host port (routes via Traefik), so host-level curling
# is not viable in CI. The HEALTHCHECK in docker-compose.yaml runs the probe
# inside the container where port 3000 is reachable.
max_wait=300
waited=0
while [ $waited -lt $max_wait ]; do
  CONTAINER=$(docker ps --filter "name=wud" --format "{{.Names}}" 2>/dev/null | head -1)
  if [ -n "$CONTAINER" ]; then
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "healthy" ]; then
      echo "WUD container is healthy"
      exit 0
    fi
  fi
  sleep 5
  waited=$((waited + 5))
done

echo "WUD health check timed out after ${max_wait}s"
exit 1
