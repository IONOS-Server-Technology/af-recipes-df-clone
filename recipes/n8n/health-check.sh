#!/usr/bin/env bash
set -euo pipefail
# CI-only health check for n8n
URL="${1:-http://localhost:5678}"
echo "Checking n8n at ${URL}/healthz ..."
curl -fsS --max-time 10 "${URL}/healthz" > /dev/null
echo "n8n is healthy."
