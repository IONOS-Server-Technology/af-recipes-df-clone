#!/usr/bin/env bash
# install.sh — Install MeshCentral via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/meshcentral/data
mkdir -p /opt/meshcentral/files
mkdir -p /opt/meshcentral/web
mkdir -p /opt/meshcentral/backups
