#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:3000}"
echo "Checking Paperless-AI at ${URL} ..."
curl -fsS --max-time 10 "${URL}/" > /dev/null
echo "Paperless-AI is healthy."
