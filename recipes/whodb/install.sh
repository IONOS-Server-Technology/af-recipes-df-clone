#!/usr/bin/env bash
# install.sh — Install WhoDB via docker-compose
set -euo pipefail

# Generate a per-server encryption key into .env before starting the container.
# WhoDB uses this to encrypt saved database connection profiles stored on disk.
# Ships empty in .env.template — a fixed value would be identical across every server.
# Idempotent: an existing non-empty value is left alone.
if [ -z "$(sed -n 's/^WHODB_ENCRYPTION_KEY=//p' .env | head -1)" ]; then
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^WHODB_ENCRYPTION_KEY=" .env; then
        sed -i "s|^WHODB_ENCRYPTION_KEY=.*|WHODB_ENCRYPTION_KEY=${value}|" .env
    else
        printf 'WHODB_ENCRYPTION_KEY=%s\n' "$value" >> .env
    fi
fi

set -a
source .env
set +a

mkdir -p /opt/whodb/data
