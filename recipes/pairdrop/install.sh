#!/usr/bin/env bash
# install.sh — Install PairDrop via docker-compose
set -euo pipefail

set -a
source .env
set +a

# PairDrop is stateless — no persistent volumes to create.
