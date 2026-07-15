#!/usr/bin/env bash
# install.sh — Install Hermes Agent via docker-compose
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Ensure Docker and Docker Compose are available
command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

# Create the host data directory world-writable so the non-root uid inside the
# container (per the Dockerfile) can write config.yaml, sessions, memories, etc.
mkdir -p /opt/hermes-agent/data
chmod 777 /opt/hermes-agent/data

# Pre-seed config.yaml with a minimal model block so the agent can answer out of
# the box when an OpenRouter key was provided. Mirrors openclaw's openclaw.json
# preseed. Provider/model can be changed later in the authenticated dashboard.
# NOTE: verify the model slug against OpenRouter's live catalogue before merge.
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  cat > /opt/hermes-agent/data/config.yaml <<'EOF'
model:
  provider: openrouter
  default: anthropic/claude-sonnet-4.5
EOF
  chmod 666 /opt/hermes-agent/data/config.yaml
fi

# Deploy application
docker-compose up -d

# Wait for the dashboard to answer (first boot is slow; 300s budget).
max_wait=300
waited=0
while [ "$waited" -lt "$max_wait" ]; do
  if curl -fsS --max-time 10 "http://127.0.0.1:9119/api/status" > /dev/null 2>&1; then
    echo "Hermes Agent is healthy after ${waited}s"
    exit 0
  fi
  sleep 5
  waited=$((waited + 5))
done

echo "Error: Hermes Agent failed to become healthy within ${max_wait}s"
exit 1
