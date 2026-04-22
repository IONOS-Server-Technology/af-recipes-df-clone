#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:3002}"
echo "Checking WUD at ${URL}/api/registries ..."
curl -fsS --max-time 10 "${URL}/api/registries" > /dev/null
echo "WUD is healthy."
