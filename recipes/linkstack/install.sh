#!/usr/bin/env bash
# install.sh — Install LinkStack via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent store: LinkStack's app files and config live under /htdocs in the container.
mkdir -p /opt/linkstack/htdocs
