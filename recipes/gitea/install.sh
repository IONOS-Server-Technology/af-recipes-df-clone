#!/usr/bin/env bash
# install.sh — Install Gitea via docker-compose
set -euo pipefail

set -a
source .env
set +a

command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

mkdir -p /opt/gitea/data
mkdir -p /opt/gitea/postgres

docker-compose up -d

max_attempts=120
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -fsS http://localhost:3000/api/healthz > /dev/null 2>&1; then
    echo "Gitea is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: Gitea failed to become healthy"
exit 1
