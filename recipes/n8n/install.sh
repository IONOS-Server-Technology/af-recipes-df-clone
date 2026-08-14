#!/usr/bin/env bash
# install.sh — Install n8n via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone. Rotating
# N8N_ENCRYPTION_KEY on a re-run would make every credential n8n has stored
# undecryptable.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex out of /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret POSTGRES_PASSWORD
af_gen_secret N8N_ENCRYPTION_KEY

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories for persistent data
mkdir -p /opt/n8n/n8n
mkdir -p /opt/n8n/postgres

# n8n runs as UID 1000 (node user) inside the container and must own its
# data directory — otherwise it fails at startup with EACCES on config load.
chown -R 1000:1000 /opt/n8n/n8n
