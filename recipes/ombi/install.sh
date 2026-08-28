#!/usr/bin/env bash
# install.sh — Install Ombi via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: Ombi configuration and database.
mkdir -p /opt/ombi/config
