#!/usr/bin/env bash
# install.sh — Install Tunarr via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/tunarr/config
