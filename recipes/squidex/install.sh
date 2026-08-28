#!/usr/bin/env bash
# install.sh — Install Squidex via docker-compose
set -euo pipefail

# Generate the MongoDB internal password once per server and write it back into
# .env. Idempotent: an existing non-empty value is left unchanged so that a
# re-run does not rotate the credential and break the running database.
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

af_gen_secret MONGO_PASSWORD

set -a
source .env
set +a

mkdir -p /opt/squidex/assets
mkdir -p /opt/squidex/mongo
