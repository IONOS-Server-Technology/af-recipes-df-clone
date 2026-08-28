#!/usr/bin/env bash
# install.sh — Install InvoiceShelf via docker-compose
set -euo pipefail

# No server-side secrets to generate: InvoiceShelf's Laravel APP_KEY is generated
# automatically by the container entrypoint on first start, and the admin account
# is created through the browser-based first-run setup wizard.

set -a
source .env
set +a

mkdir -p /opt/invoiceshelf/storage
mkdir -p /opt/invoiceshelf/modules
