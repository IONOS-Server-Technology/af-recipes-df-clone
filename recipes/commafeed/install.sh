#!/usr/bin/env bash
# install.sh — Install CommaFeed via docker-compose
set -euo pipefail

# Persistent data: CommaFeed's embedded H2 database.
# The container writes its database files to /data; mount from /opt/commafeed/data.
mkdir -p /opt/commafeed/data
