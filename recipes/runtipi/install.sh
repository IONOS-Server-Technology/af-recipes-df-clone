#!/usr/bin/env bash
# install.sh — Install Runtipi via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/runtipi/data
mkdir -p /opt/runtipi/media
mkdir -p /opt/runtipi/postgres
