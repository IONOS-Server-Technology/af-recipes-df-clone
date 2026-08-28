#!/usr/bin/env bash
# install.sh — Install AureusERP via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: bundled MySQL database and application file storage.
mkdir -p /opt/aureuserp/mysql
mkdir -p /opt/aureuserp/storage
