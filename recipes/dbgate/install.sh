#!/usr/bin/env bash
# install.sh — Install DbGate via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent storage for DbGate's saved connections and settings.
mkdir -p /opt/dbgate/data
