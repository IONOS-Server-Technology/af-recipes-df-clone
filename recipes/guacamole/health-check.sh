#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://${SERVERIP:-127.0.0.1}:8080}"
echo "Checking Apache Guacamole at ${URL}/guacamole/ ..."
curl -fsS --max-time 10 "${URL}/guacamole/" > /dev/null
echo "Apache Guacamole is healthy."
