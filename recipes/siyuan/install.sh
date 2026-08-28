#!/usr/bin/env bash
# install.sh — Install SiYuan via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/siyuan/workspace
