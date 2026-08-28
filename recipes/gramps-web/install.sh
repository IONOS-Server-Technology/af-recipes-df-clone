#!/usr/bin/env bash
# install.sh — Install Gramps Web via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: Gramps database, user store, search index, media, caches,
# Flask secret, and the Valkey task-queue data.
mkdir -p /opt/gramps-web/users
mkdir -p /opt/gramps-web/index
mkdir -p /opt/gramps-web/thumbnails
mkdir -p /opt/gramps-web/cache
mkdir -p /opt/gramps-web/secret
mkdir -p /opt/gramps-web/grampsdb
mkdir -p /opt/gramps-web/media
mkdir -p /opt/gramps-web/tmp
mkdir -p /opt/gramps-web/valkey
