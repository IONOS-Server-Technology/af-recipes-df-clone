#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://127.0.0.1:8123}"
echo "Checking Home Assistant at ${URL}/api/ ..."
curl -fsS --max-time 10 "${URL}/api/" > /dev/null
echo "Home Assistant is healthy."
