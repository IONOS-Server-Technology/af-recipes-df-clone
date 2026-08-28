#!/usr/bin/env bash
# install.sh — Install LibreSpeed via docker-compose
set -euo pipefail

# Generate this server's own PASSWORD into .env before anything reads it.
# Ships empty in the delivered file — a fixed value would be the same on every server.
# Idempotent: an existing non-empty value is left alone so a re-run does not
# invalidate results already stored under the old value.
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

af_gen_secret PASSWORD

set -a
source .env
set +a

mkdir -p /opt/librespeed/config
