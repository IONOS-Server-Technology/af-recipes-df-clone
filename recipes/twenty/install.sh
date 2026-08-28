#!/usr/bin/env bash
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship empty
# in the delivered file — a fixed value here would give every server the same credentials.
#
# Idempotent: an existing non-empty value is left alone. Postgres sets the password when it
# initialises its data directory, so rotating PG_DATABASE_PASSWORD on a re-run would lock
# Twenty out of its own database.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, no '$' for Compose to interpolate away.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret PG_DATABASE_PASSWORD
af_gen_secret ENCRYPTION_KEY
af_gen_secret APP_SECRET

set -a
source .env
set +a

mkdir -p /opt/twenty/postgres
mkdir -p /opt/twenty/storage
