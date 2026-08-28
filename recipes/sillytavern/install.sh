#!/usr/bin/env bash
# install.sh — Install SillyTavern via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/sillytavern/config
mkdir -p /opt/sillytavern/data
