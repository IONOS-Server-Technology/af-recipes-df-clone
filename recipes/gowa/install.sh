#!/usr/bin/env bash
# install.sh — Install GoWA via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: WhatsApp session files and uploaded media.
mkdir -p /opt/gowa/storages
