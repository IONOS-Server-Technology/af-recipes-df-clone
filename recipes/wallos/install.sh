#!/usr/bin/env bash
# install.sh — Install Wallos via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/wallos/db
mkdir -p /opt/wallos/uploads
