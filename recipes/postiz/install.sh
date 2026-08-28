#!/usr/bin/env bash
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone. Rotating
# POSTGRES_PASSWORD on a re-run would lock Postiz out of its own database.
af_gen_secret() {
    local key="$1" nbytes="${2:-32}" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex out of /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N"${nbytes}" /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret POSTGRES_PASSWORD 32
af_gen_secret TEMPORAL_POSTGRES_PASSWORD 32
# JWT_SECRET requires ≥64 bytes for secure session signing.
af_gen_secret JWT_SECRET 64

set -a
source .env
set +a

mkdir -p /opt/postiz/postgres
mkdir -p /opt/postiz/redis
mkdir -p /opt/postiz/uploads
mkdir -p /opt/postiz/config
mkdir -p /opt/postiz/temporal-postgres
mkdir -p /opt/postiz/elasticsearch
mkdir -p /opt/postiz/dynamicconfig

# Temporal requires this dynamic config file at startup to enable search attribute
# cache refresh, which is required when using SQL-backed visibility (via Elasticsearch).
if [ ! -f /opt/postiz/dynamicconfig/development-sql.yaml ]; then
    cat > /opt/postiz/dynamicconfig/development-sql.yaml <<'DYNCONF'
system.forceSearchAttributesCacheRefreshOnRead:
  - value: true
    constraints: {}
DYNCONF
fi

# Elasticsearch requires vm.max_map_count >= 262144 to start successfully.
if command -v sysctl &>/dev/null; then
    sysctl -w vm.max_map_count=262144 || true
fi

# Elasticsearch runs as UID 1000 (elasticsearch user) inside the container and needs
# write access to its data directory.
chown -R 1000:1000 /opt/postiz/elasticsearch
