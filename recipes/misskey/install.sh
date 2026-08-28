#!/usr/bin/env bash
# install.sh — Install Misskey via docker-compose
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

af_gen_secret POSTGRES_PASSWORD

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

mkdir -p /opt/misskey/.config
mkdir -p /opt/misskey/files
mkdir -p /opt/misskey/postgres

# Misskey reads all connection settings from a YAML config file — there is no
# per-value env-var override in this version. Write the file now so the misskey
# service has the actual database password at startup. AF_APP_DOMAIN is written
# into .env by the platform before install.sh runs.
cat > /opt/misskey/.config/default.yml <<EOF
url: https://${AF_APP_DOMAIN}/

port: 3000

db:
  host: postgres
  port: 5432
  db: misskey
  user: misskey
  pass: ${POSTGRES_PASSWORD}

redis:
  host: redis
  port: 6379

id: 'aidx'
EOF

# The misskey container runs as UID 991 (user 'misskey') and must own its media
# files directory — it writes uploaded files there at runtime.
chown -R 991:991 /opt/misskey/files
