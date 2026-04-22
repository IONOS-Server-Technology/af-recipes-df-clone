#!/usr/bin/env bash
# install.sh — Install Home Assistant via docker-compose
set -euo pipefail

set -a
source .env
set +a

command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

mkdir -p /opt/home-assistant/config

docker-compose up -d

max_attempts=120
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -fsS http://localhost:8123/api/ > /dev/null 2>&1; then
    echo "Home Assistant is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: Home Assistant failed to become healthy"
exit 1
