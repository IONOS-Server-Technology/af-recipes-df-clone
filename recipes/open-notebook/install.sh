#!/usr/bin/env bash
# install.sh — Install Open Notebook via docker-compose
set -euo pipefail

# Generate per-server secrets into .env before anything reads it.
# Idempotent: an existing non-empty value is left alone. Rotating either
# secret on a re-run would corrupt all stored credentials and encrypted data.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret DB_PASSWORD
af_gen_secret ENCRYPTION_KEY

set -a
source .env
set +a

mkdir -p /opt/open-notebook/data
mkdir -p /opt/open-notebook/surrealdb
