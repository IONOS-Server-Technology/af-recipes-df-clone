#!/usr/bin/env bash
# install.sh — Install Uptime Kuma via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/uptime-kuma/data
