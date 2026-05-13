#!/usr/bin/env bash
# install.sh — Install OpenClaw via docker-compose
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Ensure Docker and Docker Compose are available
command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

# Create host directories for persistent data
mkdir -p /opt/openclaw/config
mkdir -p /opt/openclaw/workspace

# Deploy application
docker-compose up -d

# Wait for service to be healthy (max 120 seconds)
max_attempts=120
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -fsS http://127.0.0.1:18789/healthz > /dev/null 2>&1; then
    echo "OpenClaw is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: OpenClaw failed to become healthy"
exit 1
