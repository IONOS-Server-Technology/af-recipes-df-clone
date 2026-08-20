#!/usr/bin/env bash
# health-check.sh — health check for Hermes Agent.
#
# With a URL arg: probes /api/status at that URL, then verifies the dashboard
#   root does not return a 5xx. Use this to check the app through its ingress
#   (e.g. https://hermes-agent.$BASE_DOMAIN).
# Without a URL arg (Docker/live CI mode, run on the target VM): waits for the
#   container's own Docker healthcheck to report healthy, then runs the
#   dashboard-root 5xx guard from inside the container namespace. This needs no
#   published host port — a base_domain render routes 9119 through Traefik and
#   publishes nothing on the host, so a host-side probe of :9119 would never
#   connect even while the container is healthy.
# On failure it dumps verbose diagnostics (docker ps -a, container logs, masked
# .env) for CI triage.
set -euo pipefail

URL="${1:-}"
CONTAINER_MATCH="hermes-agent"

dump_diagnostics() {
  echo "--- docker ps -a ---"
  docker ps -a 2>&1 || true
  echo "--- hermes-agent logs (last 100) ---"
  docker logs --tail 100 "$(docker ps -a --filter "name=${CONTAINER_MATCH}" --format '{{.Names}}' | head -1)" 2>&1 || true
  echo "--- .env (values masked) ---"
  sed -E 's/^([A-Za-z0-9_]+)=.*/\1=***MASKED***/' .env 2>&1 || true
}

# Follow the redirect chain from "/" and fail on any 5xx — this catches the
# class of upstream auth-gate bugs (e.g. IF-1309, where "/" redirected to an
# OAuth route that 500'd for the basic-auth-only provider) that /api/status
# stays blind to. The chain legitimately ends in 200/302/401 (login page /
# redirect / auth required), so the criterion is "not 5xx", not "exactly 200".

if [ -n "$URL" ]; then
  # URL mode: probe the given endpoint from here (host or ingress).
  max_wait=300
  waited=0
  while [ "$waited" -lt "$max_wait" ]; do
    if curl -fsS --max-time 10 "${URL}/api/status" > /dev/null 2>&1; then
      echo "Hermes Agent is healthy at ${URL}/api/status after ${waited}s"
      root_code=$(curl -sS -L -o /dev/null --max-time 10 -w '%{http_code}' "${URL}/" 2>/dev/null || true)
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
fi

# No URL provided: wait for Docker's own healthcheck (which polls
# http://127.0.0.1:9119/api/status inside the container) to report healthy.
max_wait=300
waited=0
status=none
while [ "$waited" -lt "$max_wait" ]; do
  container=$(docker ps --filter "name=${CONTAINER_MATCH}" --format '{{.Names}}' 2>/dev/null | head -1)
  if [ -n "$container" ]; then
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo unknown)
    if [ "$status" = "healthy" ]; then
      echo "Hermes Agent container ${container} is healthy after ${waited}s"

      # Run the dashboard-root 5xx guard from inside the container namespace, so
      # it works without a published host port. curl is not guaranteed in the
      # image, but python3 is (the compose HEALTHCHECK uses it). urllib follows
      # redirects; HTTPError carries the code for 4xx/5xx; anything else -> 0.
      root_code=$(docker exec "$container" python3 -c '
import sys, urllib.request, urllib.error
try:
    code = urllib.request.urlopen("http://127.0.0.1:9119/", timeout=10).status
except urllib.error.HTTPError as e:
    code = e.code
except Exception:
    code = 0
print("%03d" % code)
' 2>/dev/null || echo 000)
      case "$root_code" in
        5??|000)
          echo "ERROR: Hermes Agent dashboard root (in-container /) returned HTTP ${root_code}"
          dump_diagnostics
          exit 1
          ;;
      esac
      echo "Hermes Agent dashboard root (in-container /) is not 5xx (HTTP ${root_code})"
      exit 0
    fi
  fi
  echo "  Not ready yet... (${waited}s / ${max_wait}s, status=${status})"
  sleep 5
  waited=$((waited + 5))
done

echo "ERROR: Hermes Agent did not become healthy within ${max_wait}s"
dump_diagnostics
exit 1
