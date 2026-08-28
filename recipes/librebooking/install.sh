#!/usr/bin/env bash
# install.sh — Install LibreBooking via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent: existing non-empty values are left alone, so a re-run does not
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

af_gen_secret LB_DATABASE_PASSWORD
af_gen_secret LB_INSTALL_PASSWORD
af_gen_secret MYSQL_ROOT_PASSWORD

set -a
source .env
set +a

mkdir -p /opt/librebooking/config
mkdir -p /opt/librebooking/images
mkdir -p /opt/librebooking/reservations
mkdir -p /opt/librebooking/mariadb

docker compose up -d

# Wait for MariaDB to accept connections before running the schema importer.
echo "Waiting for MariaDB to be ready..."
WAITED=0
until docker compose exec -T mariadb mysql -u root "-p${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [ "$WAITED" -ge 120 ]; then
        echo "ERROR: MariaDB did not become ready within 120s." >&2
        exit 1
    fi
done
echo "MariaDB is ready."

# Copy the upstream schema files out of the librebooking container.
# The container is running at this point (started above); the files are baked
# into the image and available regardless of the app's HTTP health state.
SCHEMA_TMPDIR=$(mktemp -d)
trap 'rm -rf "${SCHEMA_TMPDIR}"' EXIT

docker compose cp librebooking:/var/www/html/database_schema "${SCHEMA_TMPDIR}/"
SCHEMA_DIR="${SCHEMA_TMPDIR}/database_schema"

# Run SQL directly against the MariaDB container.
# MariaDB already created the 'librebooking' database and 'lb_user' user via
# MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD — we only need the schema+data files.
MARIADB_CTR=$(docker compose ps -q mariadb)

run_sql() {
    docker exec -i "${MARIADB_CTR}" mysql \
        -u root \
        "-p${MYSQL_ROOT_PASSWORD}" \
        --abort-source-on-error \
        librebooking < "$1"
}

echo "Initializing LibreBooking database schema..."
run_sql "${SCHEMA_DIR}/create-schema.sql"

# Upgrade scripts must run in version order — see upstream INSTALLATION.rst.
# Skipping them breaks create-data.sql which depends on the upgraded schema.
while IFS= read -r -d '' dir; do
    for sql_name in schema.sql data.sql; do
        f="${dir}/${sql_name}"
        if [ -f "$f" ]; then
            echo "  Applying $(basename "${dir}")/${sql_name}..."
            run_sql "$f"
        fi
    done
done < <(find "${SCHEMA_DIR}/upgrades" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -zV)

run_sql "${SCHEMA_DIR}/create-data.sql"
echo "LibreBooking database schema initialized."
