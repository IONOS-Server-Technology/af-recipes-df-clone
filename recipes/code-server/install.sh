#!/usr/bin/env bash
# install.sh — Install Code-Server via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/code-server/data
