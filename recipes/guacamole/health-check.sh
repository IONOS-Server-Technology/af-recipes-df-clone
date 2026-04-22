#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:8080}"
echo "Checking Apache Guacamole at ${URL}/guacamole/ ..."
curl -fsS --max-time 10 "${URL}/guacamole/" > /dev/null
echo "Apache Guacamole is healthy."
