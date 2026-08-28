#!/usr/bin/env bash
# install.sh — Install Gotenberg via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Gotenberg is stateless — all conversion work is ephemeral and no persistent
# data directory is required.
