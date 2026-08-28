#!/usr/bin/env bash
# install.sh — Install Odoo via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent: an existing non-empty value is left alone, so a re-run does not
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
af_gen_secret ODOO_MASTER_PASSWORD

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories for persistent data.
mkdir -p /opt/odoo/odoo-data
mkdir -p /opt/odoo/config
mkdir -p /opt/odoo/postgres

# Write odoo.conf with the generated master password and DB credentials.
# The Odoo entrypoint reads this file on startup; admin_passwd has no env-var
# equivalent in the official image, so it must live here.
# Idempotent: only written on first run to avoid overwriting a live installation.
if [ ! -f /opt/odoo/config/odoo.conf ]; then
    cat > /opt/odoo/config/odoo.conf <<EOF
[options]
admin_passwd = ${ODOO_MASTER_PASSWORD}
db_host = postgres
db_port = 5432
db_user = odoo
db_password = ${POSTGRES_PASSWORD}
EOF
fi
