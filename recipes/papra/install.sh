#!/usr/bin/env bash
# install.sh — Install Papra via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/papra/data

# AUTH_SECRET is server-generated: create it on first boot and persist it in .env.
if [ -z "${AUTH_SECRET:-}" ]; then
    AUTH_SECRET=$(openssl rand -hex 32)
    sed -i "s|^AUTH_SECRET=.*|AUTH_SECRET=${AUTH_SECRET}|" .env
fi
