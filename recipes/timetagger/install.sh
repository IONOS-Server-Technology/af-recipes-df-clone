#!/usr/bin/env bash
# install.sh — Install TimeTagger via docker-compose
set -euo pipefail

mkdir -p /opt/timetagger/data

# TIMETAGGER_CREDENTIALS is written to .env by the AF API as a raw bcrypt hash.
# TimeTagger expects "username:hash" pairs — prepend the fixed admin username.
# Read the raw .env value without sourcing the file: sourcing would expand $$ as
# the shell PID, corrupting the bcrypt hash the AF API wrote with $$ escaping
# (RFC-001 §7.1).  Idempotent: a re-run that finds "admin:" already present is a no-op.
CRED_HASH=$(sed -n 's/^TIMETAGGER_CREDENTIALS=//p' .env | head -1)
case "$CRED_HASH" in
  admin:*) ;;
  ?*)
    {
        grep -v '^TIMETAGGER_CREDENTIALS=' .env
        printf 'TIMETAGGER_CREDENTIALS=admin:%s\n' "$CRED_HASH"
    } > .env.tmp && mv .env.tmp .env
    ;;
esac
