#!/usr/bin/env bash
# install.sh — Install Mealie via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database and uploaded files.
mkdir -p /opt/mealie/data
