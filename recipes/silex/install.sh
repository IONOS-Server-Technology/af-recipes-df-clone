#!/usr/bin/env bash
# install.sh — Install Silex via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Create host directories for Silex's filesystem storage and hosting roots.
mkdir -p /opt/silex/storage
mkdir -p /opt/silex/hosting
