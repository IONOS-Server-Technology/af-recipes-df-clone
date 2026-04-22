#!/usr/bin/env bash
# install.sh — Install Paperless-ngx via docker-compose
set -euo pipefail

set -a
source .env
set +a

command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

mkdir -p /opt/paperless-ngx/data
mkdir -p /opt/paperless-ngx/media
mkdir -p /opt/paperless-ngx/export
mkdir -p /opt/paperless-ngx/consume
mkdir -p /opt/paperless-ngx/postgres

docker-compose up -d

max_attempts=120
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -fsS http://localhost:8000/ > /dev/null 2>&1; then
    echo "Paperless-ngx is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: Paperless-ngx failed to become healthy"
exit 1
