#!/usr/bin/env bash
# install.sh — Install autobrr via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/autobrr/data
