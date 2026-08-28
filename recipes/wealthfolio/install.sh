#!/usr/bin/env bash
# install.sh — Install Wealthfolio via docker-compose
set -euo pipefail

# Generate WF_SECRET_KEY on first boot. Idempotent: an existing non-empty value
# is left alone so re-runs do not invalidate sessions signed with the old key.
# base64 output contains no shell metacharacters, so it is safe for .env without quoting.
if [ -z "$(sed -n 's/^WF_SECRET_KEY=//p' .env | head -1)" ]; then
    value="$(openssl rand -base64 32)"
    if grep -q "^WF_SECRET_KEY=" .env; then
        sed -i "s|^WF_SECRET_KEY=.*|WF_SECRET_KEY=${value}|" .env
    else
        printf 'WF_SECRET_KEY=%s\n' "$value" >>.env
    fi
fi

set -a
source .env
set +a

mkdir -p /opt/wealthfolio/data
