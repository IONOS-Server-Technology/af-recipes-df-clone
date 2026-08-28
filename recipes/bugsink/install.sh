#!/usr/bin/env bash
# install.sh — Install BugSink via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone, so a re-run does not
# invalidate data already written under the old value.
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

af_gen_secret SECRET_KEY
af_gen_secret POSTGRES_PASSWORD

# CREATE_SUPERUSER is email:password — the app only accepts this as plaintext at first boot.
# A fixed internal admin credential is generated here; the Traefik basic_auth gate is the
# customer-facing auth boundary. Run /root/auth.sh off bugsink once logged in to remove it.
if [ -z "$(sed -n 's/^CREATE_SUPERUSER=//p' .env | head -1)" ]; then
    superuser_pass="$(od -An -tx1 -N24 /dev/urandom | tr -d ' \n')"
    if grep -q "^CREATE_SUPERUSER=" .env; then
        sed -i "s|^CREATE_SUPERUSER=.*|CREATE_SUPERUSER=admin@localhost:${superuser_pass}|" .env
    else
        printf 'CREATE_SUPERUSER=admin@localhost:%s\n' "$superuser_pass" >>.env
    fi
fi

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directory for PostgreSQL persistent data.
mkdir -p /opt/bugsink/postgres
