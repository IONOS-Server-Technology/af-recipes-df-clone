#!/usr/bin/env bash
# install.sh — Install Watcharr via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database and uploaded assets.
mkdir -p /opt/watcharr/data
