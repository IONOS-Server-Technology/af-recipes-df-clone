#!/usr/bin/env bash
# install.sh — Install CyberChef via docker-compose
set -euo pipefail

set -a
source .env
set +a

# CyberChef is stateless on the server side — all operations run client-side in
# the browser. No persistent data directory is required.
