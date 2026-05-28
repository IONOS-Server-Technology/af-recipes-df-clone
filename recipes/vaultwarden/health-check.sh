#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://${SERVERIP:-127.0.0.1}:80}"
echo "Checking Vaultwarden at ${URL}/alive ..."
curl -fsS --max-time 10 "${URL}/alive" > /dev/null
echo "Vaultwarden is healthy."
