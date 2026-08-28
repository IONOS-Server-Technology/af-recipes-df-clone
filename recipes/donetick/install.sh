#!/usr/bin/env bash
# install.sh — Install Donetick via docker-compose
set -euo pipefail

# Generate JWT_SECRET at first boot. Idempotent: an existing non-empty value is left alone.
# Rotating the key on a re-run would invalidate every active session.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, and no '$' for Compose to interpolate away.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret JWT_SECRET

set -a
source .env
set +a

mkdir -p /opt/donetick/data
mkdir -p /opt/donetick/config
