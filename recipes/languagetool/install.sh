#!/usr/bin/env bash
# install.sh — Install LanguageTool via docker-compose
set -euo pipefail

set -a
source .env
set +a

# LanguageTool is stateless — no persistent data directories are needed.
