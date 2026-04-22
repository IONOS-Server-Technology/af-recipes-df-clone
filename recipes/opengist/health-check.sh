#!/usr/bin/env bash
set -euo pipefail
URL="${1:-http://localhost:6157}"
echo "Checking OpenGist at ${URL} ..."
curl -fsS --max-time 10 "${URL}/" > /dev/null
echo "OpenGist is healthy."
