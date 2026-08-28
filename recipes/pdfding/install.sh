#!/usr/bin/env bash
# install.sh — Install PdfDing via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/pdfding/data

# Generate a Django secret key on first install; leave any existing value alone.
if [ -z "${SECRET_KEY:-}" ]; then
    SECRET_KEY=$(openssl rand -hex 50)
    sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|" .env
fi
