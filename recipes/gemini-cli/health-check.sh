#!/usr/bin/env bash
set -euo pipefail
# CI-only health check for Gemini CLI
echo "Checking Gemini CLI installation ..."
command -v gemini > /dev/null 2>&1 || { echo "gemini binary not found"; exit 1; }
gemini --version > /dev/null 2>&1 || { echo "gemini --version failed"; exit 1; }
echo "Gemini CLI is installed: $(gemini --version)"
