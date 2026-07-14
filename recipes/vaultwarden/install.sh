#!/usr/bin/env bash
# install.sh — Install Vaultwarden via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/vaultwarden/data
