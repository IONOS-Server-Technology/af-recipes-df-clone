#!/usr/bin/env bash
# install.sh — Install Hi.Events via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone, so a re-run does not
# invalidate data already written under the old value.
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

# Laravel APP_KEY must be in the form "base64:<32 random bytes base64-encoded>".
# Using openssl or head+base64 — no external dependency beyond coreutils.
af_gen_app_key() {
    local key="APP_KEY" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    value="base64:$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_app_key
af_gen_secret JWT_SECRET
af_gen_secret POSTGRES_PASSWORD

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories for persistent data.
mkdir -p /opt/hievents/storage
mkdir -p /opt/hievents/postgres
