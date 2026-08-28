#!/usr/bin/env bash
# install.sh — Install TaxHacker via docker-compose
set -euo pipefail

# Generate per-server secrets into .env before anything reads it. Both keys ship
# empty in the delivered file so no two servers share a secret.
#
# Idempotent: an existing non-empty value is left alone. Re-rolling BETTER_AUTH_SECRET
# on a re-run would invalidate all active sessions.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, no '$' for Compose to interpolate.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret POSTGRES_PASSWORD
af_gen_secret BETTER_AUTH_SECRET

set -a
source .env
set +a

# Create host directories for persistent data.
mkdir -p /opt/taxhacker/uploads
mkdir -p /opt/taxhacker/postgres
