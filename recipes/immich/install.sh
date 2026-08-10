#!/usr/bin/env bash
set -euo pipefail

# Generate this VM's own secrets into .env before anything reads it (IF-1417). The key
# ships empty in .env.template because nothing substitutes values into it (IF-944) — a
# literal committed to the repo would give every customer's photo database the same
# password.
#
# Idempotent on purpose: an existing non-empty value is left alone. Postgres sets the
# password when it initialises its data directory, so rotating it on a re-run would lock
# immich out of its own database.
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

af_gen_secret DB_PASSWORD

set -a
source .env
set +a

mkdir -p /opt/immich/upload
mkdir -p /opt/immich/model-cache
mkdir -p /opt/immich/postgres
