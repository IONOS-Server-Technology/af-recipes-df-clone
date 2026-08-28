#!/usr/bin/env bash
# install.sh — Install draw.io via docker-compose
set -euo pipefail

set -a
source .env
set +a

# draw.io is stateless on the server side — diagrams are stored client-side.
# No persistent data directory is required.
