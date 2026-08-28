#!/usr/bin/env bash
# install.sh — Install Yopass via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Yopass stores secrets ephemerally in Memcached; no persistent data directories needed.
