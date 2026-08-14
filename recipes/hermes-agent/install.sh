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

# Create the host data directory world-writable so the non-root uid inside the
# container (per the Dockerfile) can write config.yaml, sessions, memories, etc.
mkdir -p /opt/hermes-agent/data
chmod 777 /opt/hermes-agent/data

# Pre-seed config.yaml with a minimal model block so the agent can answer out of
# the box when an OpenRouter key was provided. Mirrors openclaw's openclaw.json
# preseed. Provider and model can be changed later from the dashboard.
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  cat > /opt/hermes-agent/data/config.yaml <<'EOF'
model:
  provider: openrouter
  default: anthropic/claude-sonnet-4.5
EOF
  chmod 666 /opt/hermes-agent/data/config.yaml
fi
