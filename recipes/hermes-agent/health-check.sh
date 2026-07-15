#!/usr/bin/env bash
# health-check.sh — health check for Hermes Agent.
# Polls the unauthenticated /api/status endpoint. With a URL arg it probes that
# URL; otherwise it uses ${SERVERIP:-127.0.0.1}:9119. On timeout it dumps verbose
# diagnostics (docker ps -a, container logs, masked .env) for CI triage.
set -euo pipefail

URL="${1:-http://${SERVERIP:-127.0.0.1}:9119}"
CONTAINER_MATCH="hermes-agent"

max_wait=300
waited=0
while [ "$waited" -lt "$max_wait" ]; do
  if curl -fsS --max-time 10 "${URL}/api/status" > /dev/null 2>&1; then
    echo "Hermes Agent is healthy at ${URL}/api/status after ${waited}s"
    exit 0
  fi
  echo "  Not ready yet... (${waited}s / ${max_wait}s)"
  sleep 5
  waited=$((waited + 5))
done

echo "ERROR: Hermes Agent did not become healthy within ${max_wait}s"
echo "--- docker ps -a ---"
docker ps -a 2>&1 || true
echo "--- hermes-agent logs (last 100) ---"
docker logs --tail 100 "$(docker ps -a --filter "name=${CONTAINER_MATCH}" --format '{{.Names}}' | head -1)" 2>&1 || true
echo "--- .env (values masked) ---"
sed -E 's/^([A-Za-z0-9_]+)=.*/\1=***MASKED***/' .env 2>&1 || true
exit 1
