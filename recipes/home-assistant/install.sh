#!/usr/bin/env bash
# install.sh — Install Home Assistant via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/home-assistant/config
