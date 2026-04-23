#!/usr/bin/env bash
set -euo pipefail
# CI-only health check for Ollama
URL="${1:-http://127.0.0.1:11434}"
echo "Checking Ollama at ${URL}/api/tags ..."
curl -fsS --max-time 10 "${URL}/api/tags" > /dev/null
echo "Ollama is healthy."
