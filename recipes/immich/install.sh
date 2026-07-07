#!/usr/bin/env bash
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/immich/upload
mkdir -p /opt/immich/model-cache
mkdir -p /opt/immich/postgres
