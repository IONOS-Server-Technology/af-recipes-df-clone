#!/usr/bin/env bash
# install.sh — Install RustDesk Server via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: hbbs writes its ed25519 keypair here on first start.
# hbbr reads the same keypair to authenticate relay sessions.
mkdir -p /opt/rustdesk/data
