#!/usr/bin/env bash
# install.sh — Install Fusion via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database and feed metadata.
mkdir -p /opt/fusion-rss/data
