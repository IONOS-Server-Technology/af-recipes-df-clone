#!/usr/bin/env bash
# health-check.sh — health check for Hermes Agent.
# Polls the unauthenticated /api/status endpoint, then verifies the dashboard
# root does not return a 5xx. With a URL arg it probes that URL; otherwise it
# uses ${SERVERIP:-127.0.0.1}:9119. On failure it dumps verbose diagnostics
# (docker ps -a, container logs, masked .env) for CI triage.
set -euo pipefail

URL="${1:-http://${SERVERIP:-127.0.0.1}:9119}"
CONTAINER_MATCH="hermes-agent"

dump_diagnostics() {
  echo "--- docker ps -a ---"
  docker ps -a 2>&1 || true
  echo "--- hermes-agent logs (last 100) ---"
  docker logs --tail 100 "$(docker ps -a --filter "name=${CONTAINER_MATCH}" --format '{{.Names}}' | head -1)" 2>&1 || true
  echo "--- .env (values masked) ---"
  sed -E 's/^([A-Za-z0-9_]+)=.*/\1=***MASKED***/' .env 2>&1 || true
}

max_wait=300
waited=0
while [ "$waited" -lt "$max_wait" ]; do
  if curl -fsS --max-time 10 "${URL}/api/status" > /dev/null 2>&1; then
    echo "Hermes Agent is healthy at ${URL}/api/status after ${waited}s"

    # /api/status is unauthenticated and never exercises the dashboard UI.
    # Follow the redirect chain from "/" and fail on any 5xx — this catches the
    # class of upstream auth-gate bugs (e.g. IF-1309, where "/" redirected to an
    # OAuth route that 500'd for the basic-auth-only provider) that /api/status
    # stays blind to. The chain legitimately ends in 200/302/401 (login page /
    # redirect / auth required), so the criterion is "not 5xx", not "exactly 200".
    root_code=$(curl -sS -L -o /dev/null --max-time 10 -w '%{http_code}' "${URL}/" 2>/dev/null || echo 000)
    case "$root_code" in
      5??|000)
        echo "ERROR: Hermes Agent dashboard root ${URL}/ returned HTTP ${root_code}"
        dump_diagnostics
        exit 1
        ;;
    esac
    echo "Hermes Agent dashboard root ${URL}/ is not 5xx (HTTP ${root_code})"
    exit 0
  fi
  echo "  Not ready yet... (${waited}s / ${max_wait}s)"
  sleep 5
  waited=$((waited + 5))
done

echo "ERROR: Hermes Agent did not become healthy within ${max_wait}s"
dump_diagnostics
exit 1
