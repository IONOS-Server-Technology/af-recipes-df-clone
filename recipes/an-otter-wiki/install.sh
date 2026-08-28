#!/usr/bin/env bash
# install.sh — Install An Otter Wiki via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/an-otter-wiki/data
