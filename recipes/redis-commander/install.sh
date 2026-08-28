#!/usr/bin/env bash
# install.sh — Install Redis Commander via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent storage for the bundled Redis server's data.
mkdir -p /opt/redis-commander/redis-data
