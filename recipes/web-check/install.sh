#!/usr/bin/env bash
# install.sh — Install Web-Check via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Web-Check is stateless on the server side — no persistent data directory is required.
