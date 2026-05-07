#!/usr/bin/env bash
set -euo pipefail
# CI-only health check for Portainer
URL="${1:-https://${SERVERIP:-127.0.0.1}:9443}"
echo "Checking Portainer at ${URL}/api/status ..."
curl -fsSk --max-time 10 "${URL}/api/status" > /dev/null
echo "Portainer is healthy."
