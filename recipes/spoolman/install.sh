#!/usr/bin/env bash
# install.sh — Install Spoolman via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database and Spoolman state.
mkdir -p /opt/spoolman/data
