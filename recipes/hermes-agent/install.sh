#!/usr/bin/env bash
# install.sh — Prepare Hermes Agent for docker-compose.
# Prep-only (IF-1139 convention): mkdir/chown/config-preseed here, the shared
# compose-up.sh helper brings the containers up; docker/compose availability
# is already checked once in the OS-image bootstrap.
set -euo pipefail

# Generate this VM's own session secret into .env before anything reads it (IF-1417). It
# ships empty in .env.template because nothing substitutes values into that file (IF-944) —
# it used to carry a placeholder, which gave every customer's VM the same signing key.
#
# The dashboard *password* is no longer generated here: af-api derives it from the
# customer's server password and the renderer writes the scrypt hash into .env at compose
# time (IF-1454). Only the session secret is still VM-local, because it signs cookies and
# has no counterpart the customer would ever type.
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
# preseed. Provider/model can be changed later in the authenticated dashboard.
# NOTE: verify the model slug against OpenRouter's live catalogue before merge.
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  cat > /opt/hermes-agent/data/config.yaml <<'EOF'
model:
  provider: openrouter
  default: anthropic/claude-sonnet-4.5
EOF
  chmod 666 /opt/hermes-agent/data/config.yaml
fi
