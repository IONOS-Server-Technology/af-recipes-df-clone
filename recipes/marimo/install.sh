#!/usr/bin/env bash
# install.sh — Install Marimo via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent storage for notebooks created in the editor.
mkdir -p /opt/marimo/notebooks
