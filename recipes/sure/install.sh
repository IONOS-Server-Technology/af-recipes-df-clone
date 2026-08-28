#!/usr/bin/env bash
# install.sh — Install Sure via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone, so a re-run does not
# invalidate data already written under the old value.
af_gen_secret() {
    local key="$1" nbytes="${2:-32}" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex out of /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N"${nbytes}" /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

# SECRET_KEY_BASE: Rails requires at least 64 bytes (128 hex chars) for session security.
af_gen_secret SECRET_KEY_BASE 64
af_gen_secret POSTGRES_PASSWORD 32

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

mkdir -p /opt/sure/postgres
mkdir -p /opt/sure/redis
