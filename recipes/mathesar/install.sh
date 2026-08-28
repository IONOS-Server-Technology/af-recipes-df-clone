#!/usr/bin/env bash
set -euo pipefail

# Generate per-server secrets into .env before the stack reads them. Empty in
# the delivered file, so no two servers share a database password or Django key.
#
# Idempotent: an existing non-empty value is left alone. Postgres sets the
# password on first init; rotating it on a re-run would lock Mathesar out of
# its own database.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret DB_PASSWORD
af_gen_secret SECRET_KEY

set -a
source .env
set +a

mkdir -p /opt/mathesar/media
mkdir -p /opt/mathesar/static
mkdir -p /opt/mathesar/postgres
