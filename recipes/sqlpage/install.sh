#!/usr/bin/env bash
# install.sh — Install SQLPage via docker-compose
set -euo pipefail

set -a
source .env
set +a

# SQLPage serves SQL files from /var/www/site inside the container and stores its
# embedded SQLite database there. Create the host directory so Compose can bind-mount
# it without daemon-created root-owned files.
mkdir -p /opt/sqlpage/data
