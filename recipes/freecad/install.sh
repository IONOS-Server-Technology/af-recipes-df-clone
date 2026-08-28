#!/usr/bin/env bash
# install.sh — Install FreeCAD via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/freecad/config
