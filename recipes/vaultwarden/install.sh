#!/usr/bin/env bash
# install.sh — Install Vaultwarden via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/vaultwarden/data
# The application writes here as root, so the directory keeps root as its owner — but
# 755 lets any other account on the machine walk in, and the files the container creates
# land at 644. Restricting the directory is what actually protects them: whatever mode a
# file ends up with, nobody but root can reach it through a 700 directory. Same treatment
# hermes-agent already gets.
# Holds db.sqlite3 and rsa_key.pem — the vault database and the key that signs
# its sessions.
chmod 700 /opt/vaultwarden/data
