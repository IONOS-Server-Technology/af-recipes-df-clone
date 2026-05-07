#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://${SERVERIP:-127.0.0.1}:80}"
echo "Checking Runtipi at ${URL} ..."
curl -fsS --max-time 10 "${URL}/" > /dev/null
echo "Runtipi is healthy."
