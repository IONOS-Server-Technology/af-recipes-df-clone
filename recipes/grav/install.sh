#!/usr/bin/env bash
# install.sh — Install Grav via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/grav/user
