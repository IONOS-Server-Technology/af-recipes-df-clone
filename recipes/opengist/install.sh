#!/usr/bin/env bash
# install.sh — Install OpenGist via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/opengist/data
