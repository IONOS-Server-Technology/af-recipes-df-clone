#!/usr/bin/env bash
# install.sh — Install ErsatzTV via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: ErsatzTV configuration, database, and media metadata.
mkdir -p /opt/ersatztv/data
