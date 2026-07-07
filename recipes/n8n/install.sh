#!/usr/bin/env bash
# install.sh — Install n8n via docker-compose
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Create host directories for persistent data
mkdir -p /opt/n8n/n8n
mkdir -p /opt/n8n/postgres

# n8n runs as UID 1000 (node user) inside the container and must own its
# data directory — otherwise it fails at startup with EACCES on config load.
chown -R 1000:1000 /opt/n8n/n8n
