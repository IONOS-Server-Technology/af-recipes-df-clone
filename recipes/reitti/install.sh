#!/usr/bin/env bash
set -euo pipefail

# Generate the PostGIS password once per server. Idempotent: an existing
# non-empty value is left unchanged so that a re-run does not lock Reitti out
# of its own database.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret POSTGIS_PASSWORD

set -a
source .env
set +a

mkdir -p /opt/reitti/data
mkdir -p /opt/reitti/postgis
mkdir -p /opt/reitti/redis
mkdir -p /opt/reitti/tile-cache
