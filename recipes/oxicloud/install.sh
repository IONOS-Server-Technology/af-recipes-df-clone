#!/usr/bin/env bash
set -euo pipefail

# Generate a per-server database password into .env before anything reads it.
# Ships empty in the delivered file so no two servers share a credential.
# Idempotent: an existing non-empty value is left untouched — Postgres initialises
# its data directory with the password set at first boot, so overwriting it on a
# re-run would lock oxicloud out of its own database.
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

af_gen_secret DB_PASSWORD

set -a
source .env
set +a

mkdir -p /opt/oxicloud/data
mkdir -p /opt/oxicloud/postgres
