#!/usr/bin/env bash
# install.sh — Install TubeSync via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/tubesync/config
mkdir -p /opt/tubesync/downloads
