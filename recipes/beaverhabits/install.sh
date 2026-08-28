#!/usr/bin/env bash
# install.sh — Install BeaverHabits via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/beaverhabits/data
