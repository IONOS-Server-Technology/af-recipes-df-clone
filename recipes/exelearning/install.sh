#!/usr/bin/env bash
# install.sh — Install eXeLearning via docker-compose
set -euo pipefail

# Generate per-server secrets into .env. Idempotent: an existing non-empty value is left alone.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    value="$(od -An -tx1 -N64 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret APP_SECRET
af_gen_secret API_JWT_SECRET

set -a
source .env
set +a

mkdir -p /opt/exelearning/data
