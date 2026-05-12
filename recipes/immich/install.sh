#!/usr/bin/env bash
set -euo pipefail

set -a
source .env
set +a

command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Error: Docker Compose plugin not available"; exit 1; }

mkdir -p /opt/immich/upload
mkdir -p /opt/immich/model-cache
mkdir -p /opt/immich/postgres

docker compose up -d

max_attempts=180
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -fsS http://localhost:2283/api/server/ping > /dev/null 2>&1; then
    echo "Immich is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 2
done

echo "Error: Immich failed to become healthy within 6 minutes"
exit 1
