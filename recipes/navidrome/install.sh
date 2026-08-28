#!/usr/bin/env bash
# install.sh — Install Navidrome via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database and cache.
mkdir -p /opt/navidrome/data
# Music library mount — customers populate this via SFTP or another recipe.
mkdir -p /opt/navidrome/music
