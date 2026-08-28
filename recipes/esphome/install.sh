#!/usr/bin/env bash
# install.sh — Install ESPHome via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent storage for ESPHome device YAML configuration files.
mkdir -p /opt/esphome/config
