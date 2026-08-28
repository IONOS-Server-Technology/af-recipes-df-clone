#!/usr/bin/env bash
# install.sh — Install Lowcoder via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent state: all Lowcoder data (bundled MongoDB, Redis, and uploaded
# assets) lands in /lowcoder-stacks inside the container.
mkdir -p /opt/lowcoder/stacks
