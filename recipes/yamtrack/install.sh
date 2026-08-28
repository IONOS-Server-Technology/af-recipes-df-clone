#!/usr/bin/env bash
# install.sh — Install Yamtrack via docker-compose
set -euo pipefail

# Generate this server's own Django secret key into .env before anything reads it.
# Ships empty in the delivered file — a fixed value would be the same key on every server.
#
# Idempotent: an existing non-empty value is left alone, so a re-run does not
# invalidate session data already signed under the old key.
af_gen_secret() {
    local key="$1" nbytes="${2:-32}" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N"${nbytes}" /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

# Django requires a long random string for cryptographic signing of sessions and cookies.
af_gen_secret SECRET_KEY 50

set -a
source .env
set +a

# Persistent data: SQLite database, uploaded media, and Redis task-queue state.
mkdir -p /opt/yamtrack/data
mkdir -p /opt/yamtrack/redis
