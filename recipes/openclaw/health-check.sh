#!/usr/bin/env bash
set -euo pipefail
# CI-only health check for OpenClaw
URL="${1:-http://127.0.0.1:18789}"
echo "Checking OpenClaw at ${URL}/healthz ..."
curl -fsS --max-time 10 "${URL}/healthz" > /dev/null
echo "OpenClaw is healthy."
