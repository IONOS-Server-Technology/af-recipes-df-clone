#!/usr/bin/env bash
# install.sh — Install Homarr via docker-compose
set -euo pipefail

# Generate this server's own encryption key into .env before the container reads it.
# Ships empty in the delivered file so no two servers share a key.
# Idempotent: an existing non-empty value is left alone so a re-run does not
# invalidate data already encrypted under the old key.
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

af_gen_secret SECRET_ENCRYPTION_KEY

set -a
source .env
set +a

mkdir -p /opt/homarr/data
