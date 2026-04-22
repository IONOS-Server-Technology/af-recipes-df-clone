#!/usr/bin/env bash
set -euo pipefail
# CI-only health check for Portainer
URL="${1:-https://localhost:9443}"
echo "Checking Portainer at ${URL}/api/status ..."
curl -fsSk --max-time 10 "${URL}/api/status" > /dev/null
echo "Portainer is healthy."
