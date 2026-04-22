#!/usr/bin/env bash
# install.sh — Install AdGuard Home via docker-compose
set -euo pipefail

set -a
source .env
set +a

command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

mkdir -p /opt/adguard-home/work
mkdir -p /opt/adguard-home/conf

docker-compose up -d

max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -fsS http://localhost:3000/ > /dev/null 2>&1; then
    echo "AdGuard Home is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: AdGuard Home failed to become healthy"
exit 1
