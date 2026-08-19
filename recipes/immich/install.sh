#!/usr/bin/env bash
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship empty
# in the delivered file — a fixed value here would give every server's photo database
# the same password.
#
# Idempotent on purpose: an existing non-empty value is left alone. Postgres sets the
# password when it initialises its data directory, so rotating it on a re-run would lock
# immich out of its own database.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex out of /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
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

mkdir -p /opt/immich/upload
mkdir -p /opt/immich/model-cache
mkdir -p /opt/immich/postgres
# The application writes here as root, so the directory keeps root as its owner — but
# 755 lets any other account on the machine walk in, and the files the container creates
# land at 644. Restricting the directory is what actually protects them: whatever mode a
# file ends up with, nobody but root can reach it through a 700 directory. Same treatment
# hermes-agent already gets.
# upload holds the customer's photo library. postgres is left alone: the database
# image sets its own owner and mode there, and 700 is already what it wants.
chmod 700 /opt/immich/upload
chmod 700 /opt/immich/model-cache
