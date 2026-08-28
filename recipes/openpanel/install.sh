#!/usr/bin/env bash
# install.sh — Install OpenPanel via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would give every server the same
# secrets, making all instances trivially compromisable.
#
# Idempotent: an existing non-empty value is left alone. Postgres initialises its data
# directory with the password at first start, so rotating on a re-run would lock
# openpanel-api out of its own database.
af_gen_secret() {
    local key="$1" nbytes="${2:-32}" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, no '$' for Compose to interpolate.
    value="$(od -An -tx1 -N"${nbytes}" /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret POSTGRES_PASSWORD 32
af_gen_secret COOKIE_SECRET 64

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

mkdir -p /opt/openpanel/postgres
mkdir -p /opt/openpanel/clickhouse
