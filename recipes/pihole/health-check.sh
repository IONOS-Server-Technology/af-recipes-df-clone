#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:8080}"
echo "Checking Pi-hole at ${URL}/admin/ ..."
curl -fsS --max-time 10 "${URL}/admin/" > /dev/null
echo "Pi-hole is healthy."
