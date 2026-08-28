#!/usr/bin/env bash
# install.sh — Install LNbits via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database and application state.
mkdir -p /opt/lnbits/data
