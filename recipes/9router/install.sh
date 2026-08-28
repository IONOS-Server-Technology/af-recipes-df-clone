#!/usr/bin/env bash
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/9router/data

# JWT_SECRET is server-generated: create it on first boot and persist it in .env.
if [ -z "${JWT_SECRET:-}" ]; then
    JWT_SECRET=$(openssl rand -hex 32)
    sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" .env
fi
