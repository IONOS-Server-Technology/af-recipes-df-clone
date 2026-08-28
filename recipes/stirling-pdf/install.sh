#!/usr/bin/env bash
# install.sh — Install Stirling PDF via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: app configuration and logs.
mkdir -p /opt/stirling-pdf/configs
mkdir -p /opt/stirling-pdf/logs
