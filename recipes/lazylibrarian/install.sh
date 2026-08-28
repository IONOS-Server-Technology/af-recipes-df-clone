#!/usr/bin/env bash
# install.sh — Install LazyLibrarian via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/lazylibrarian/config
mkdir -p /opt/lazylibrarian/books
