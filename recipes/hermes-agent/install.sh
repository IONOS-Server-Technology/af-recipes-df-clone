#!/usr/bin/env bash
# install.sh — Prepare Hermes Agent for docker-compose.
# Preparation only: create directories, set ownership and pre-seed the config here.
# The containers are started afterwards by the shared compose-up.sh helper.
set -euo pipefail

# Generate this server's own session secret into .env before anything reads it. It ships
# empty in the delivered file, so no two servers share a signing key.
#
# The dashboard password is not generated here: it is derived from the server password
# and filled in as a hash before delivery. Only the session secret is generated locally,
# because it signs cookies and is never typed by anyone.
#
# Idempotent on purpose: a non-empty value is left alone, so the session secret does not
# rotate under logged-in users on a re-run.
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

af_gen_secret HERMES_DASHBOARD_BASIC_AUTH_SECRET

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# The dashboard service drops to the image's own `hermes` user before it runs
# (s6-rc.d/dashboard/run does `s6-setuidgid hermes`), and that user is uid 10000 with
# /opt/data as its home — the directory mounted here. So give it to that uid instead of
# to everyone: wud holds read-write access to all of /opt to manage every app's compose
# file, and a world-writable data directory means any process on the host can rewrite
# this agent's config.
mkdir -p /opt/hermes-agent/data
chown -R 10000:10000 /opt/hermes-agent/data
# chown alone does not clear mode bits an older recipe version already set, so a
# re-install on top of a 777 directory would keep the world-writable bit.
chmod -R 700 /opt/hermes-agent/data

# Pre-seed config.yaml with a minimal model block so the agent can answer out of
# the box when an OpenRouter key was provided. Mirrors openclaw's openclaw.json
# preseed. Provider and model can be changed later from the dashboard.
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  # Created at its final mode and owner before anything is written to it, so the file
  # never exists world-readable. chown rather than `install -o 10000`: the base image
  # ships uutils coreutils, whose install accepts a numeric owner only when a passwd
  # entry with that id exists, and the host has no user at uid 10000.
  install -m 600 /dev/null /opt/hermes-agent/data/config.yaml
  chown 10000:10000 /opt/hermes-agent/data/config.yaml
  cat > /opt/hermes-agent/data/config.yaml <<'EOF'
model:
  provider: openrouter
  default: anthropic/claude-sonnet-4.5
EOF
fi
