#!/usr/bin/env bash
# install.sh — Install OpenClaw via docker-compose
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Create host directories with world-writable perms so the node user in the
# container can write the config (openclaw runs as uid 1000, not root).
mkdir -p /opt/openclaw/config
mkdir -p /opt/openclaw/workspace
chmod 777 /opt/openclaw/config /opt/openclaw/workspace

# Pre-seed config so the gateway starts without requiring interactive setup.
echo '{"gateway":{"controlUi":{"dangerouslyAllowHostHeaderOriginFallback":true}}}' > /opt/openclaw/config/openclaw.json
chmod 666 /opt/openclaw/config/openclaw.json
