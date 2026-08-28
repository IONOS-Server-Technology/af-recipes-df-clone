#!/usr/bin/env bash
# install.sh — Install Verdaccio via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/verdaccio/conf /opt/verdaccio/storage /opt/verdaccio/plugins

# Write the Verdaccio config on first install. max_users: -1 disables self-registration
# so the pre-seeded admin account is the only entry point (IF-1420).
CONFIG_FILE=/opt/verdaccio/conf/config.yaml
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'YAML'
storage: /verdaccio/storage
plugins: /verdaccio/plugins
auth:
  htpasswd:
    file: /verdaccio/conf/htpasswd
    algorithm: bcrypt
    max_users: -1
uplinks:
  npmjs:
    url: https://registry.npmjs.org/
packages:
  '@*/*':
    access: $authenticated
    publish: $authenticated
    proxy: npmjs
  '**':
    access: $authenticated
    publish: $authenticated
    proxy: npmjs
web:
  enable: true
log:
  type: stdout
  format: pretty
  level: http
listen: 0.0.0.0:4873
YAML
fi

# Seed the admin user into the htpasswd file. VERDACCIO_ADMIN_PASSWORD_HASH is a
# bcrypt hash of ROOT_PASSWORD written by af-api (IF-1420). With max_users: -1 in
# config.yaml, this pre-seeded account is the only way in — self-registration is off.
HTPASSWD_FILE=/opt/verdaccio/conf/htpasswd
if [ ! -f "$HTPASSWD_FILE" ]; then
    printf 'admin:%s\n' "${VERDACCIO_ADMIN_PASSWORD_HASH}" > "$HTPASSWD_FILE"
fi

# Verdaccio container runs as UID 10001; grant write access so it can update storage.
chown -R 10001:10001 /opt/verdaccio/conf /opt/verdaccio/storage /opt/verdaccio/plugins
