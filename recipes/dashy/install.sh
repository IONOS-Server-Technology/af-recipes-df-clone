#!/usr/bin/env bash
# install.sh — Install Dashy via docker-compose
set -euo pipefail

# Create the data directory for Dashy's dashboard configuration.
# Dashy reads /app/user-data/conf.yml at startup; if absent it falls back to
# its built-in demo config, which the customer can edit and save via the UI.
mkdir -p /opt/dashy/user-data
