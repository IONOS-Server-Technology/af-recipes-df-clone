#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:8384}"
echo "Checking Syncthing at ${URL}/rest/noauth/health ..."
curl -fsS --max-time 10 "${URL}/rest/noauth/health" > /dev/null
echo "Syncthing is healthy."
