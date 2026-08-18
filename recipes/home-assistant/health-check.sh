#!/usr/bin/env bash
set -euo pipefail

# Without a URL argument the caller is not on the app's own network — the recipe test
# harness runs this from outside the Docker daemon's namespace, where the app's port is
# not reachable and a single probe can only fail. Wait for the containers' own
# healthchecks instead, which is the same information the app would give over HTTP.
#
# The project name is this script's own directory, which is what Compose uses when the
# harness starts the stack with --project-directory.
wait_for_healthy() {
    local project max_wait=300 waited=0 ids id state status code name pending
    project=$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
    while [ "$waited" -lt "$max_wait" ]; do
        # -aq rather than -q: a container that crashed drops out of the running list, and a
        # readiness check that stops seeing it would report the whole stack healthy while
        # part of it is down. Every inspect is guarded, because a container can disappear
        # between this snapshot and the next call — which is precisely what happens in the
        # crashing case this is meant to diagnose, and an unguarded status would turn an
        # informative timeout into a hard failure under 'set -e'.
        ids=$(docker ps -aq --filter "label=com.docker.compose.project=$project" 2>/dev/null || true)
        pending=""
        for id in $ids; do
            state=$(docker inspect --format '{{.State.Status}}' "$id" 2>/dev/null || echo unknown)
            status=$(docker inspect \
                --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
                "$id" 2>/dev/null || echo unknown)
            name=$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null || echo "$id")
            if [ "$state" = running ]; then
                # 'none' means the service declares no healthcheck; running is all it can say.
                if [ "$status" = healthy ] || [ "$status" = none ]; then
                    continue
                fi
            elif [ "$state" = exited ]; then
                # A one-shot service that finished successfully is not a failure.
                code=$(docker inspect --format '{{.State.ExitCode}}' "$id" 2>/dev/null || echo 1)
                if [ "$code" = 0 ]; then
                    continue
                fi
                state="exited($code)"
            fi
            pending="$pending ${name}=${state}/${status}"
        done
        if [ -n "$ids" ] && [ -z "$pending" ]; then
            echo "all containers of '$project' are healthy after ${waited}s"
            return 0
        fi
        echo "  Not ready yet... (${waited}s / ${max_wait}s)${pending}"
        sleep 5
        waited=$((waited + 5))
    done
    echo "ERROR: '$project' did not become healthy within ${max_wait}s" >&2
    docker ps -a --filter "label=com.docker.compose.project=$project" 2>&1 || true
    ids=$(docker ps -aq --filter "label=com.docker.compose.project=$project" 2>/dev/null || true)
    for id in $ids; do
        echo "--- logs $(docker inspect --format '{{.Name}}' "$id" 2>/dev/null || echo "$id") ---"
        docker logs --tail 60 "$id" 2>&1 || true
    done
    return 1
}

if [ $# -eq 0 ]; then
    wait_for_healthy
    exit
fi
URL="${1:-http://${SERVERIP:-127.0.0.1}:8123}"
echo "Checking Home Assistant at ${URL}/api/ ..."
curl -fsS --max-time 10 "${URL}/api/" > /dev/null
echo "Home Assistant is healthy."
