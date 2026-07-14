#!/usr/bin/env bash
# install.sh — Install Portainer via docker-compose
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Create host directories for persistent data
mkdir -p /opt/portainer/data
