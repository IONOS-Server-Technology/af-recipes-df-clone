#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://${SERVERIP:-127.0.0.1}:3000}"
echo "Checking Gitea at ${URL}/api/healthz ..."
curl -fsS --max-time 10 "${URL}/api/healthz" > /dev/null
echo "Gitea is healthy."
