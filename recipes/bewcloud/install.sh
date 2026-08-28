#!/usr/bin/env bash
# install.sh — Install bewCloud via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone, so a re-run does not
# invalidate data already written under the old value (e.g. rotating JWT_SECRET would
# invalidate all existing bewCloud sessions).
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

af_gen_secret POSTGRESQL_PASSWORD
af_gen_secret JWT_SECRET
af_gen_secret PASSWORD_SALT

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories for persistent data.
mkdir -p /opt/bewcloud/data-files
mkdir -p /opt/bewcloud/db

# Write the bewCloud TypeScript config. allowSignups: false means only the first
# visitor can register (bewCloud's own design — the first signup always succeeds
# and becomes admin regardless of this flag, then the door closes).
cat > /opt/bewcloud/bewcloud.config.ts << BEWCLOUD_CONFIG
import { PartialDeep } from './lib/types.ts';
import type { Config } from './lib/types.ts';

const config: PartialDeep<Config> = {
  auth: {
    baseUrl: 'https://${AF_APP_DOMAIN}',
    allowSignups: false,
  },
};

export default config;
BEWCLOUD_CONFIG
