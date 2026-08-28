#!/usr/bin/env bash
# install.sh — Install SearXNG via docker-compose
set -euo pipefail

# Generate this server's own secret into .env before anything reads it. Ships
# empty so the value is unique per server — a fixed value would be the same
# on every fleet member.
#
# Idempotent: an existing non-empty value is left alone.
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

af_gen_secret SEARXNG_SECRET

set -a
source .env
set +a

mkdir -p /opt/searxng/config
