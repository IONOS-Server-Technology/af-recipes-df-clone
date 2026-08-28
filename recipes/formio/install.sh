#!/usr/bin/env bash
# install.sh — Install Form.io via docker-compose
set -euo pipefail

# Generate internal secrets once per server. Idempotent: an existing non-empty
# value is left unchanged so that a re-run does not rotate credentials and
# break the running database or invalidate existing JWT tokens.
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

af_gen_secret MONGO_PASSWORD
af_gen_secret JWT_SECRET

set -a
source .env
set +a

mkdir -p /opt/formio/uploads
mkdir -p /opt/formio/mongo
