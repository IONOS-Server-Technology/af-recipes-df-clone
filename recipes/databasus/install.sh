#!/usr/bin/env bash
# install.sh — Install Databasus via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/databasus/data
