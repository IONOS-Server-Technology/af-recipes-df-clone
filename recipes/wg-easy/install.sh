#!/usr/bin/env bash
# install.sh — Install WireGuard Easy via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/wg-easy/data
