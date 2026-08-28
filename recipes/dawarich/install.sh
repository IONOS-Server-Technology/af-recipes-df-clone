#!/usr/bin/env bash
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent: an existing non-empty value is left alone. Postgres sets its password when
# it initialises its data directory, so rotating it on a re-run would lock Dawarich out.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex out of /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N64 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret SECRET_KEY_BASE
af_gen_secret POSTGRES_PASSWORD

set -a
source .env
set +a

mkdir -p /opt/dawarich/postgres
mkdir -p /opt/dawarich/redis
mkdir -p /opt/dawarich/public
mkdir -p /opt/dawarich/watched
mkdir -p /opt/dawarich/storage
