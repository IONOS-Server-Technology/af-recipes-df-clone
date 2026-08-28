#!/usr/bin/env bash
# install.sh — Install Password Pusher via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/password-pusher/storage
