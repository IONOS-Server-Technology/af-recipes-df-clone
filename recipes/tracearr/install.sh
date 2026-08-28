#!/usr/bin/env bash
# install.sh — Install Tracearr via docker-compose
set -euo pipefail

# Generate per-server secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would give every server
# the same JWT/cookie/database secret.
#
# Idempotent: an existing non-empty value is left alone. The TimescaleDB
# password is set at DB init time; rotating it on re-run would lock
# Tracearr out of its own database.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret JWT_SECRET
af_gen_secret COOKIE_SECRET
af_gen_secret DB_PASSWORD

set -a
source .env
set +a

mkdir -p /opt/tracearr/data
mkdir -p /opt/tracearr/db
