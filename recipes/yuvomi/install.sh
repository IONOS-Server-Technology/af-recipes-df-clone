#!/usr/bin/env bash
# install.sh — Install Yuvomi via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads them.
# They ship empty — a fixed value here would be identical on every server.
#
# Idempotent: an existing non-empty value is left alone so a re-run does not
# break the database or sessions already initialised with the old value.
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

af_gen_secret SESSION_SECRET
af_gen_secret DB_ENCRYPTION_KEY

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Persistent data directory for the SQLite database and app files.
mkdir -p /opt/yuvomi/data
