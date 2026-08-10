#!/usr/bin/env bash
# install.sh — Install OpenGist via docker-compose
set -euo pipefail

# Generate this VM's own secrets into .env before anything reads it (IF-1417). The keys
# ship empty in .env.template because nothing substitutes values into it (IF-944) — a
# literal committed to the repo would be the same secret on every customer VM.
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

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

mkdir -p /opt/opengist/data
