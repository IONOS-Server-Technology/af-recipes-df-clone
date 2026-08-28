#!/usr/bin/env bash
# install.sh — Install PrivateBin via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/privatebin/data

# Upstream's own docs (PrivateBin/docker-nginx-fpm-alpine README) require this
# volume to be owned by UID 65534 / GID 82 - the image's nginx/php-fpm process
# runs as that user and cannot write to /srv/data otherwise. Idempotent: safe
# to re-run on every install.
chown 65534:82 /opt/privatebin/data
