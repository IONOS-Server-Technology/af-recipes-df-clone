#!/usr/bin/env bash
# install.sh — Install SFTPGo via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database, host keys, and uploaded files.
mkdir -p /opt/sftpgo/data
