#!/usr/bin/env bash
# install.sh — Install LibreDesk via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone. Rotating
# ENCRYPTION_KEY on a re-run would make every credential LibreDesk has stored
# undecryptable.
af_gen_secret() {
    local key="$1" nbytes="${2:-32}" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex out of /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N"${nbytes}" /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret POSTGRES_PASSWORD 32
# ENCRYPTION_KEY must be exactly 32 hex chars (16 bytes) per LibreDesk's config.toml [app] requirement.
af_gen_secret ENCRYPTION_KEY 16

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories for persistent data
mkdir -p /opt/libredesk/postgres
mkdir -p /opt/libredesk/uploads
mkdir -p /opt/libredesk/redis

# Write config.toml for LibreDesk. The encryption_key and DB password are server-specific
# secrets generated above — they must not ship as literals in the delivered files.
cat > /opt/libredesk/config.toml <<EOF
[app]
address = "0.0.0.0:9000"
encryption_key = "${ENCRYPTION_KEY}"

[db]
host = "postgres"
port = 5432
user = "libredesk"
password = "${POSTGRES_PASSWORD}"
name = "libredesk"
ssl_mode = "disable"

[redis]
url = "redis://redis:6379"
EOF
