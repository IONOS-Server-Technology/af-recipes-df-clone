#!/usr/bin/env bash
# install.sh — Install AnyType Server via docker-compose
set -euo pipefail

set -a
source .env
set +a

command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

mkdir -p /opt/anytype-server/coordinator
mkdir -p /opt/anytype-server/filenode
mkdir -p /opt/anytype-server/node
mkdir -p /opt/anytype-server/mongo
mkdir -p /opt/anytype-server/minio

docker-compose up -d

max_attempts=120
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if nc -z localhost 4830 > /dev/null 2>&1; then
    echo "AnyType Server (coordinator) is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: AnyType Server failed to become healthy"
exit 1
