#!/usr/bin/env bash
set -euo pipefail

# Generate the API key once per server and inject it into the shlink container
# as INITIAL_API_KEY. Idempotent: an existing non-empty value is left unchanged
# so a re-run does not revoke the key.
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

af_gen_secret SHLINK_INITIAL_API_KEY

set -a
source .env
set +a

mkdir -p /opt/shlink/data
