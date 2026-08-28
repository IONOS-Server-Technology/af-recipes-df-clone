#!/usr/bin/env bash
# install.sh — Install Mailpit via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/mailpit/data
