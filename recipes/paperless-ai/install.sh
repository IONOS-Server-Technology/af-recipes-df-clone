#!/usr/bin/env bash
# install.sh — Install Paperless-AI via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/paperless-ai/data
