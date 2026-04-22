#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:51821}"
echo "Checking WireGuard Easy at ${URL} ..."
curl -fsS --max-time 10 "${URL}/" > /dev/null
echo "WireGuard Easy is healthy."
