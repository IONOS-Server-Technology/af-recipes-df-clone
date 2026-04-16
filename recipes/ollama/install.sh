#!/usr/bin/env bash
# install.sh — Install Ollama via docker-compose
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Ensure Docker and Docker Compose are available
command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

# Create host directories for persistent data
mkdir -p /opt/ollama/ollama

# Deploy application
docker-compose up -d

# Wait for service to be healthy (max 60 seconds)
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if docker-compose exec -T ollama curl -fsS http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Ollama is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: Ollama failed to become healthy"
exit 1
