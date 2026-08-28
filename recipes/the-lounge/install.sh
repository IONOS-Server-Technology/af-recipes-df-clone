#!/usr/bin/env bash
# install.sh — Install The Lounge via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: The Lounge stores user configs and logs under THELOUNGE_HOME.
mkdir -p /opt/the-lounge/data/users

# Write the admin user config. The Lounge reads users from
# ${THELOUNGE_HOME}/users/<name>.json; 'password' must be a bcrypt hash.
# Using printf %s to pass ADMIN_PASSWORD_HASH verbatim — bcrypt hashes contain
# literal dollar signs that would be re-expanded in an unquoted heredoc.
printf '{\n  "password": "%s",\n  "log": false,\n  "networks": [],\n  "sessions": {}\n}\n' \
    "$ADMIN_PASSWORD_HASH" > /opt/the-lounge/data/users/admin.json
chmod 600 /opt/the-lounge/data/users/admin.json
