#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:80}"
echo "Checking Vaultwarden at ${URL}/alive ..."
curl -fsS --max-time 10 "${URL}/alive" > /dev/null
echo "Vaultwarden is healthy."
