#!/usr/bin/env bash
# install.sh — Install Dataline via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: Dataline's SQLite database and configuration.
mkdir -p /opt/dataline/data
