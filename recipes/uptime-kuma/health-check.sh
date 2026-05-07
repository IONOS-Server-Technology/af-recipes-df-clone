#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://${SERVERIP:-127.0.0.1}:3001}"
echo "Checking Uptime Kuma at ${URL}/api/entry-page ..."
curl -fsS --max-time 10 "${URL}/api/entry-page" > /dev/null
echo "Uptime Kuma is healthy."
