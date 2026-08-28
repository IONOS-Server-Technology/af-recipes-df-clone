#!/usr/bin/env bash
# install.sh — Install Karaoke Eternal via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/karaoke-eternal/data
