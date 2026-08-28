#!/usr/bin/env bash
# install.sh — Install Livebook via docker-compose
set -euo pipefail

# Create the persistent data directory for notebooks before Compose starts.
mkdir -p /opt/livebook/data
