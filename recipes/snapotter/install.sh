#!/usr/bin/env bash
# install.sh — Install SnapOtter via docker-compose
set -euo pipefail

# Generate per-server secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value would be the same secret on every server.
# Idempotent: an existing non-empty value is left alone.
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

af_gen_secret POSTGRES_PASSWORD
af_gen_secret REDIS_PASSWORD

set -a
source .env
set +a

mkdir -p /opt/snapotter/data
mkdir -p /opt/snapotter/workspace
mkdir -p /opt/snapotter/postgres
mkdir -p /opt/snapotter/redis
