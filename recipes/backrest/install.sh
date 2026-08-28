#!/usr/bin/env bash
# install.sh — Install Backrest via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/backrest/config /opt/backrest/data /opt/backrest/cache

# Seed the admin account into config.json before the first container start so the
# interactive sign-up wizard is bypassed. BACKREST_PASSWORD is a bcrypt hash of
# ROOT_PASSWORD, supplied by af-api (generated_from: "bcrypt:ROOT_PASSWORD").
# The hash is inserted via printf %s so shell metacharacters in the value are not
# re-interpreted, and bcrypt characters ($, /, .) need no JSON escaping.
#
# "version" is required and must be the current config schema version (6, as of
# backrest v1.14.1 - internal/config/migrations/migrations.go's CurrentVersion is
# len(migrations)). Confirmed real bug: omitting it defaults to 0, which backrest
# only accepts for a truly empty config (proto.Equal to the zero value) - any
# non-empty config.json with version 0, like this seeded one, hits
# "config version 0 is invalid" and crash-loops forever.
CONFIG_FILE=/opt/backrest/config/config.json
if [ ! -f "$CONFIG_FILE" ]; then
    printf '{"version":6,"auth":{"users":[{"name":"admin","passwordBcrypt":"%s"}]}}\n' \
        "${BACKREST_PASSWORD}" > "$CONFIG_FILE"
fi
