#!/usr/bin/env bash
# install.sh — Install OpenCloud via docker-compose
set -euo pipefail

set -a
source .env
set +a

# OpenCloud runs as UID/GID 1000:1000 — directories must be writable by that user.
mkdir -p /opt/opencloud/config
mkdir -p /opt/opencloud/data
chown 1000:1000 /opt/opencloud/config
chown 1000:1000 /opt/opencloud/data
