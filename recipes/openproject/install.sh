#!/usr/bin/env bash
# install.sh — Install OpenProject via docker-compose
set -euo pipefail

# Generate per-server secrets into .env before anything reads it.
# Idempotent: an existing non-empty value is left alone.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # 64 hex bytes = 128-char string; no '$' for Compose to interpolate away.
    value="$(od -An -tx1 -N64 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret POSTGRES_PASSWORD
af_gen_secret SECRET_KEY_BASE

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories for persistent data.
mkdir -p /opt/openproject/pgdata
mkdir -p /opt/openproject/assets
