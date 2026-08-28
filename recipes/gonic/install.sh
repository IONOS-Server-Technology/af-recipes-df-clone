#!/usr/bin/env bash
# install.sh — Install Gonic via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database, music library, transcoding cache, podcasts.
mkdir -p /opt/gonic/data
mkdir -p /opt/gonic/music
mkdir -p /opt/gonic/cache
mkdir -p /opt/gonic/podcasts
