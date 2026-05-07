#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://${SERVERIP:-127.0.0.1}:51821}"
echo "Checking WireGuard Easy at ${URL} ..."
curl -fsS --max-time 10 "${URL}/" > /dev/null
echo "WireGuard Easy is healthy."
