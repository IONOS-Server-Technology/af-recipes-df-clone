#!/usr/bin/env bash
set -euo pipefail

# Generate server-local secrets into .env before anything reads it.
# Idempotent: existing non-empty values are left alone, so a re-run does not
# invalidate data already written under the old value.
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

af_gen_secret MYSQL_ROOT_PASSWORD
af_gen_secret DB_PASSWORD

set -a
source .env
set +a

mkdir -p /opt/ampache/data
mkdir -p /opt/ampache/music
