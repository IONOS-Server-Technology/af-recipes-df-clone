#!/usr/bin/env bash
# install.sh — Install Glance via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/glance/config /opt/glance/assets

# Generate a random auth secret key on first install and persist it to .env.
# Glance requires this to be base64-encoded and decode to exactly 64 raw
# bytes (AUTH_SECRET_KEY_LENGTH in internal/glance/auth.go) - a hex string
# does not satisfy this, and openssl wraps base64 output at 64 chars/line
# for inputs this size, so the newlines must be stripped before storing it
# as a single-line env var.
if [ -z "${GLANCE_SECRET_KEY:-}" ]; then
    GLANCE_SECRET_KEY=$(openssl rand -base64 64 | tr -d '\n')
    echo "GLANCE_SECRET_KEY=${GLANCE_SECRET_KEY}" >> .env
fi

# Write the Glance config file. The ${...} tokens are written literally so
# that Glance's own env-var substitution resolves them from the container
# environment at startup (supported since v0.8.0).
cat > /opt/glance/config/glance.yml << 'GLANCE_CONFIG'
server:
  host: 0.0.0.0
  port: 8080

auth:
  secret-key: ${GLANCE_SECRET_KEY}
  users:
    admin:
      password-hash: ${GLANCE_ADMIN_PASSWORD_HASH}

pages:
  - name: Home
    columns:
      - size: full
        widgets: []
GLANCE_CONFIG
