#!/usr/bin/env bash
# install.sh — Install Sonarr via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Sonarr stores its config and internal SQLite database under /config.
mkdir -p /opt/sonarr/config
