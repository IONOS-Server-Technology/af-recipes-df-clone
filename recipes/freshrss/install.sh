#!/usr/bin/env bash
# install.sh — Install FreshRSS via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/freshrss/data
mkdir -p /opt/freshrss/extensions
