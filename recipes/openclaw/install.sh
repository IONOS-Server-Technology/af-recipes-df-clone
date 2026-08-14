#!/usr/bin/env bash
# install.sh — Install OpenClaw via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship empty
# in the delivered file — a fixed value here would be the same gateway token on every
# server, and the gateway will not start without one.
#
# Idempotent on purpose: an existing non-empty value is left alone, so a re-run does not
# invalidate a token the customer has already configured in a client.
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

af_gen_secret OPENCLAW_GATEWAY_TOKEN

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories with world-writable perms so the node user in the
# container can write the config (openclaw runs as uid 1000, not root).
mkdir -p /opt/openclaw/config
mkdir -p /opt/openclaw/workspace
chmod 777 /opt/openclaw/config /opt/openclaw/workspace

# Pre-seed config so the gateway starts without requiring interactive setup.
echo '{"gateway":{"controlUi":{"dangerouslyAllowHostHeaderOriginFallback":true}}}' > /opt/openclaw/config/openclaw.json
chmod 666 /opt/openclaw/config/openclaw.json
