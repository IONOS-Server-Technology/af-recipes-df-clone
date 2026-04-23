#!/usr/bin/env bash
# install.sh — Install OpenGist via docker-compose
set -euo pipefail

set -a
source .env
set +a

command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

mkdir -p /opt/opengist/data

docker-compose up -d

max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -fsS http://127.0.0.1:6157/ > /dev/null 2>&1; then
    echo "OpenGist is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: OpenGist failed to become healthy"
exit 1
