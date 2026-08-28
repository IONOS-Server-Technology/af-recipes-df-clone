# Match containers by name substring, not by an assumed Compose project
# label — the harness that runs this script prefixes the project name
# (e.g. "afpre-redis-commander"), so a project-label filter derived from this script's
# own directory ("redis-commander") never matches and silently waits out the full
# timeout against zero containers. Every container Compose creates for this
# stack is named "<project>-<service>-<index>", and the project name always
# contains this recipe's own slug regardless of the harness's prefix
# convention, so a name substring match is robust to all of them.
wait_for_healthy() {
    local max_wait=300 waited=0 ids id state status code name pending
    while [ "$waited" -lt "$max_wait" ]; do
        # -aq rather than -q: a container that crashed drops out of the running
        # list; keeping all containers in view lets us detect the crash rather
        # than silently reporting healthy with half the stack down.
        ids=$(docker ps -aq --filter "name=(^|-)redis-commander-" 2>/dev/null || true)
        pending=""
        for id in $ids; do
            state=$(docker inspect --format '{{.State.Status}}' "$id" 2>/dev/null || echo unknown)
            status=$(docker inspect \
                --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
                "$id" 2>/dev/null || echo unknown)
            name=$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null || echo "$id")
            if [ "$state" = running ]; then
                if [ "$status" = healthy ] || [ "$status" = none ]; then
                    continue
                fi
            elif [ "$state" = exited ]; then
                code=$(docker inspect --format '{{.State.ExitCode}}' "$id" 2>/dev/null || echo 1)
                if [ "$code" = 0 ]; then
                    continue
                fi
                state="exited($code)"
            fi
            pending="$pending ${name}=${state}/${status}"
        done
        if [ -n "$ids" ] && [ -z "$pending" ]; then
            echo "all redis-commander containers are healthy after ${waited}s"
            return 0
        fi
        echo "  Not ready yet... (${waited}s / ${max_wait}s)${pending}"
        sleep 5
        waited=$((waited + 5))
    done
    echo "ERROR: redis-commander did not become healthy within ${max_wait}s" >&2
    docker ps -a --filter "name=(^|-)redis-commander-" 2>&1 || true
    ids=$(docker ps -aq --filter "name=(^|-)redis-commander-" 2>/dev/null || true)
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
# Secondary/manual path: probe the web UI from an external host.
# Redis Commander returns 401 when HTTP auth is configured; accept any HTTP
# response as evidence the daemon is running — a connection failure is the
# only signal that actually means "not ready".
URL="${1:-http://${SERVERIP:-127.0.0.1}:8081}"
echo "Checking Redis Commander at ${URL} ..."
http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${URL}" || echo 000)
if [ "$http_code" = "200" ] || [ "$http_code" = "401" ]; then
    echo "Redis Commander is healthy (HTTP ${http_code})."
else
    echo "Redis Commander is not healthy (HTTP ${http_code})." >&2
    exit 1
fi
