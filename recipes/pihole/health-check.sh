#!/usr/bin/env bash
set -euo pipefail
set -a; source .env; set +a
URL="${1:-http://${WG_INTERFACE_IP:-10.8.0.1}:8080}"
echo "Checking Pi-hole at ${URL}/admin/ ..."
curl -fsS --max-time 10 "${URL}/admin/" > /dev/null
echo "Pi-hole is healthy."
