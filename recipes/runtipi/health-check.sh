#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:80}"
echo "Checking Runtipi at ${URL} ..."
curl -fsS --max-time 10 "${URL}/" > /dev/null
echo "Runtipi is healthy."
