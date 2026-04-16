#!/usr/bin/env bash
# install.sh — Install Portainer via docker-compose
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Ensure Docker and Docker Compose are available
command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

# Create host directories for persistent data
mkdir -p /opt/portainer/data

# Deploy application
docker-compose up -d

# Wait for service to be healthy (max 60 seconds)
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if docker-compose exec -T portainer curl -fsS http://localhost:9000 > /dev/null 2>&1; then
    echo "Portainer is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: Portainer failed to become healthy"
exit 1
