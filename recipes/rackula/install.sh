#!/usr/bin/env bash
# install.sh — Install Rackula via docker-compose
set -euo pipefail

# Generate per-server secrets into .env before anything reads it.
# Idempotent: existing non-empty values are left alone, so re-runs don't
# invalidate data already written under the old value.
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

af_gen_secret RACKULA_API_WRITE_TOKEN

set -a
source .env
set +a

# Persistent data: rack layout storage for the API sidecar.
# The API runs as uid 1001; pre-create and chown so it can write on first boot.
mkdir -p /opt/rackula/data
chown -R 1001:1001 /opt/rackula/data
