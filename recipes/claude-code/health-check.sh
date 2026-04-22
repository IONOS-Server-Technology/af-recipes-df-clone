#!/usr/bin/env bash
set -euo pipefail
# CI-only health check for Claude Code
echo "Checking Claude Code installation ..."
command -v claude > /dev/null 2>&1 || { echo "claude binary not found"; exit 1; }
claude --version > /dev/null 2>&1 || { echo "claude --version failed"; exit 1; }
echo "Claude Code is installed: $(claude --version)"
