#!/usr/bin/env bash
# install.sh — Install Budibase via docker-compose
set -euo pipefail

# Generate per-server secrets before the container first reads them. They ship
# empty in the delivered file — a fixed value would be the same secret on every server.
# Idempotent: an existing non-empty value is left unchanged.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, and no '$' for Compose to interpolate.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret JWT_SECRET
af_gen_secret INTERNAL_API_KEY
af_gen_secret MINIO_ACCESS_KEY
af_gen_secret MINIO_SECRET_KEY
af_gen_secret REDIS_PASSWORD
af_gen_secret COUCHDB_PASSWORD

# Load the completed configuration.
set -a
source .env
set +a

# Create host directory for persistent data (CouchDB attachments, MinIO objects, app files).
mkdir -p /opt/budibase/data
