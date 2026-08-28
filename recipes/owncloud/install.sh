#!/usr/bin/env bash
# install.sh — Install ownCloud Infinite Scale via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/owncloud/config /opt/owncloud/data
