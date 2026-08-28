#!/usr/bin/env bash
# install.sh — Install Plik via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: uploaded files and SQLite metadata database.
# The DB file is pre-created so Docker bind-mounts it as a file, not a directory.
mkdir -p /opt/plik/data
touch /opt/plik/plik.db
