#!/usr/bin/env bash
# install.sh — Install Apache Guacamole via docker-compose
set -euo pipefail

set -a
source .env
set +a

command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

mkdir -p /opt/guacamole/postgres
mkdir -p /opt/guacamole/init

# Generate database initialization script
docker run --rm guacamole/guacamole:1.5.5 /opt/guacamole/bin/initdb.sh --postgresql > /opt/guacamole/init/initdb.sql

docker-compose up -d

max_attempts=120
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -fsS http://127.0.0.1:8080/guacamole/ > /dev/null 2>&1; then
    echo "Apache Guacamole is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: Apache Guacamole failed to become healthy"
exit 1
