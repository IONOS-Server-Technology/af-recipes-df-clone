#!/usr/bin/env bash
# install.sh — Install Mazanoke via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Mazanoke is stateless on the server side — all image processing runs client-side
# in the browser using WebAssembly. No persistent data directory is required.
