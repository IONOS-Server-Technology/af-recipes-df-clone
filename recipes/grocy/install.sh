#!/usr/bin/env bash
# install.sh — Install Grocy via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/grocy/config
