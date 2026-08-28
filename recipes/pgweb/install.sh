#!/usr/bin/env bash
# install.sh — Install Pgweb via docker-compose
set -euo pipefail

# Pgweb is stateless — it stores nothing on disk between sessions.
# The reverse-proxy basic-auth gate is configured by the platform (traefik-net),
# not by anything this script sets up.
