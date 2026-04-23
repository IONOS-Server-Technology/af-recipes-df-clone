#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://127.0.0.1:8000}"
echo "Checking Paperless-ngx at ${URL} ..."
curl -fsS --max-time 10 "${URL}/" > /dev/null
echo "Paperless-ngx is healthy."
