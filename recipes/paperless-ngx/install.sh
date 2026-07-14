#!/usr/bin/env bash
# install.sh — Install Paperless-ngx via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/paperless-ngx/data
mkdir -p /opt/paperless-ngx/media
mkdir -p /opt/paperless-ngx/export
mkdir -p /opt/paperless-ngx/consume
mkdir -p /opt/paperless-ngx/postgres
