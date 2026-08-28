#!/usr/bin/env bash
# install.sh — Install PatchMon via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone, so a re-run does not
# invalidate data already written under the old value.
#
# POSTGRES_PASSWORD, REDIS_PASSWORD, and JWT_SECRET are declared as metadata parameters
# with generated_from: "argon2:ROOT_PASSWORD" — af-api writes those before install.sh
# runs, so af_gen_secret is a no-op for them. SESSION_SECRET has no metadata parameter
# and no generated_from, so install.sh generates it here.
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

af_gen_secret SESSION_SECRET

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directory for persistent database data.
mkdir -p /opt/patchmon/postgres
