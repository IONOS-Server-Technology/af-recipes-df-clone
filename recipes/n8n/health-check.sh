#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://127.0.0.1:5678}"
MAX_WAIT=300
INTERVAL=10
ELAPSED=0

echo "Waiting for n8n at ${URL}/healthz ..."

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -fsS --max-time 5 "${URL}/healthz" > /dev/null 2>&1; then
        echo "n8n is healthy after ${ELAPSED}s"
        exit 0
    fi
    echo "  Not ready yet... (${ELAPSED}s / ${MAX_WAIT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: n8n did not become healthy within ${MAX_WAIT}s"
echo "--- docker ps -a ---"
docker ps -a 2>&1 || true
echo "--- n8n container logs (last 100 lines) ---"
docker logs --tail 100 n8n-n8n-1 2>&1 || true
echo "--- n8n inspect (state) ---"
docker inspect n8n-n8n-1 2>&1 | python3 -c "import sys,json; d=json.load(sys.stdin); s=d[0].get('State',{}); print('Status:', s.get('Status')); print('ExitCode:', s.get('ExitCode')); print('Error:', s.get('Error'))" 2>/dev/null || true
echo "--- /opt/n8n/.env (masked) ---"
cat /opt/n8n/.env 2>&1 | sed 's/=.*/=REDACTED/' || true
exit 1
