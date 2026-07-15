#!/usr/bin/env bash
# install.sh — Prepare Hermes Agent for docker-compose.
# Prep-only (IF-1139 convention): mkdir/chown/config-preseed here, the shared
# compose-up.sh helper brings the containers up; docker/compose availability
# is already checked once in the OS-image bootstrap.
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

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
