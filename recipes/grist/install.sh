#!/usr/bin/env bash
# install.sh — Install Grist via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database and documents stored at /persist inside the container.
mkdir -p /opt/grist/data
