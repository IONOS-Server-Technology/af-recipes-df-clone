#!/usr/bin/env bash
# install.sh — Install Kanboard via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database, uploaded files, and plugins.
mkdir -p /opt/kanboard/data
