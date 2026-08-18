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

# Create host directories owned by the node user in the container (openclaw
# runs as uid 1000, not root) so it can write its own config — chown instead of
# chmod 777/666, so the dirs aren't writable by every other process on the host
# (e.g. wud, which holds RW access to all of /opt to manage every app's compose file).
mkdir -p /opt/openclaw/config
mkdir -p /opt/openclaw/workspace
chown -R 1000:1000 /opt/openclaw/config /opt/openclaw/workspace
# chown alone doesn't clear mode bits an older recipe version may have already set —
# re-installing on top of a pre-fix install (777) would otherwise keep the world-writable
# bit despite the ownership change. uid 1000 is the sole writer, so 700 is enough.
chmod -R 700 /opt/openclaw/config /opt/openclaw/workspace

# Pre-seed config so the gateway starts without requiring interactive setup.
# allowedOrigins (rather than the dangerouslyAllowHostHeaderOriginFallback escape
# hatch) is what openclaw's own `security audit` recommends: it pins the
# WebSocket/Control-UI origin check to this app's actual domain instead of
# trusting the Host header, without weakening DNS-rebinding protection.
# `install` creates the file at its final mode before anything is written to it, so there
# is never a window where openclaw.json exists at default (world-readable) perms.
#
# Ownership is set with chown rather than `install -o 1000`, which aborts the whole script
# under `set -e`: the base image ships uutils coreutils (the Rust rewrite, default from
# Ubuntu 26.04), whose `install` accepts a numeric owner only if a passwd entry with that
# id exists -- and the AF VM has no user at uid 1000. It resolves 65534 fine because
# `nobody` is in passwd, which is why this only ever bit here. `chown` takes the number
# either way. Verified on a test VM: install (uutils coreutils) 0.8.0,
# `install: invalid user: '1000'`, and `+1000` fails the same way.
install -m 600 /dev/null /opt/openclaw/config/openclaw.json
chown 1000:1000 /opt/openclaw/config/openclaw.json
printf '{"gateway":{"controlUi":{"allowedOrigins":["https://%s"]}}}' "${AF_APP_DOMAIN}" > /opt/openclaw/config/openclaw.json
