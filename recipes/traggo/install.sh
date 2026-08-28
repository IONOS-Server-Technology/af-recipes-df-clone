#!/usr/bin/env bash
# install.sh — Install Traggo via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database written to the container's working directory.
mkdir -p /opt/traggo/data
