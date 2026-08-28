#!/usr/bin/env bash
# install.sh — Install LakeFS via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent storage for the local database and blockstore.
mkdir -p /opt/lakefs/data
