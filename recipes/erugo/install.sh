#!/usr/bin/env bash
# install.sh — Install Erugo via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/erugo/storage
