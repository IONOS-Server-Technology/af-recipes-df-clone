#!/usr/bin/env bash
# install.sh — Install Apprise API via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/apprise-api/data
