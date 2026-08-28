#!/usr/bin/env bash
# install.sh — Install Adminer via docker-compose
set -euo pipefail

# Adminer is stateless — it stores nothing on disk between sessions.
# The reverse-proxy basic-auth gate is configured by the platform (traefik-net),
# not by anything this script sets up.
