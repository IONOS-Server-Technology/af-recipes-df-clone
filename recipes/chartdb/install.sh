#!/usr/bin/env bash
# install.sh — Install ChartDB via docker-compose
set -euo pipefail

# ChartDB is stateless — all diagram state lives in the browser (IndexedDB/localStorage).
# No host directories are needed. Access is gated by Traefik basic-auth (metadata.yaml:
# basic_auth: true) using the customer's server password.
