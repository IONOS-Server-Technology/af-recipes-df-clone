#!/usr/bin/env bash
# install.sh — Install Buzz via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads them.
# They ship empty — a fixed value here would be identical on every server.
#
# Idempotent: an existing non-empty value is left alone so a re-run does not
# break a database or relay already initialised with the old value.
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

af_gen_secret POSTGRES_PASSWORD
af_gen_secret REDIS_PASSWORD
af_gen_secret BUZZ_S3_ACCESS_KEY
af_gen_secret BUZZ_S3_SECRET_KEY
# 32 bytes = 64 hex chars — the correct length for a Nostr private key.
af_gen_secret BUZZ_RELAY_PRIVATE_KEY
af_gen_secret BUZZ_GIT_HOOK_HMAC_SECRET

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Persistent data directories.
mkdir -p /opt/buzz/postgres
mkdir -p /opt/buzz/redis
mkdir -p /opt/buzz/minio
mkdir -p /opt/buzz/git

# The postgres/redis/minio images self-chown their data dirs via their own
# entrypoints, but ghcr.io/block/buzz:main runs as a fixed uid=1000 gid=1000
# ("buzz") with no such logic - it just tries to write and fails. Without
# this, the container crash-loops on boot: "BUZZ_GIT_PACK_CACHE_PATH=
# /data/git/.pack-cache could not be created: Permission denied (os error
# 13)" (confirmed live: root-owned bind mount -> immediate crash loop;
# chown 1000:1000 -> healthy within seconds, no other change needed).
chown -R 1000:1000 /opt/buzz/git
