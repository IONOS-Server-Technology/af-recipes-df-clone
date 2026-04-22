#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:8000}"
echo "Checking Paperless-ngx at ${URL} ..."
curl -fsS --max-time 10 "${URL}/" > /dev/null
echo "Paperless-ngx is healthy."
