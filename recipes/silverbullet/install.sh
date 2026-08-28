#!/usr/bin/env bash
# install.sh — Install SilverBullet via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: Markdown notes and attachments stored as plain files.
mkdir -p /opt/silverbullet/space
