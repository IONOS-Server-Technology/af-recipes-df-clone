#!/usr/bin/env bash
# install.sh — Install Moodist via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/moodist/data
