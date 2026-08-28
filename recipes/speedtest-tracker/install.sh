#!/usr/bin/env bash
# install.sh — Install Speedtest Tracker via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent: existing non-empty values are left alone, so a re-run does not
# invalidate data already written under the old value.
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

# Speedtest Tracker (Laravel) requires APP_KEY in base64:<32-byte-base64> format.
af_gen_app_key() {
    local key="APP_KEY" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    value="base64:$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d '\n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_app_key
af_gen_secret ADMIN_PASSWORD

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

mkdir -p /opt/speedtest-tracker/data
