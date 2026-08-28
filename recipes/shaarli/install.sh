#!/usr/bin/env bash
# install.sh — Install Shaarli via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: bookmarks, config, and cache stored in a flat-file structure.
mkdir -p /opt/shaarli/data
