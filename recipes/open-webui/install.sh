#!/usr/bin/env bash
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship empty
# in the delivered file — a fixed value here would sign every server's sessions with the
# same key.
#
# Idempotent on purpose: an existing non-empty value is left alone, so a re-run does not
# invalidate the sessions of everyone currently logged in.
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

af_gen_secret WEBUI_SECRET_KEY

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories for persistent data
mkdir -p /opt/open-webui/data
mkdir -p /opt/open-webui/ollama
# The application writes here as root, so the directory keeps root as its owner — but
# 755 lets any other account on the machine walk in, and the files the container creates
# land at 644. Restricting the directory is what actually protects them: whatever mode a
# file ends up with, nobody but root can reach it through a 700 directory. Same treatment
# hermes-agent already gets.
# data holds webui.db (accounts, chats, API keys) and the vector store.
chmod 700 /opt/open-webui/data
chmod 700 /opt/open-webui/ollama
