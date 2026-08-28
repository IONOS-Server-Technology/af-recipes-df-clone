#!/usr/bin/env bash
# install.sh — Install Yucca via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: camera config, recordings, and motion-detection state.
mkdir -p /opt/yucca/data
