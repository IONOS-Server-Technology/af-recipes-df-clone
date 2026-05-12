#!/usr/bin/env bash
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Ensure Docker and Docker Compose are available
command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

# Create host directories for persistent data
mkdir -p /opt/open-webui/data
mkdir -p /opt/open-webui/ollama

# Deploy application
docker-compose up -d

# Wait for Open WebUI to become healthy (Ollama startup + model cache init can be slow)
max_attempts=120
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if curl -fsS http://127.0.0.1:3004/health > /dev/null 2>&1; then
    echo "open-webui is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: open-webui failed to become healthy within 120 seconds"
exit 1
