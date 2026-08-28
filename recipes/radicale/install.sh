#!/usr/bin/env bash
# install.sh — Install Radicale via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: CalDAV/CardDAV collections.
mkdir -p /opt/radicale/data
