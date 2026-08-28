#!/usr/bin/env bash
# install.sh — Install BentoPDF via docker-compose
set -euo pipefail

# BentoPDF is stateless — it stores nothing on disk between sessions.
# All PDF operations run client-side in the browser via WASM; no files are
# written to the host. The reverse-proxy basic-auth gate is configured by
# the platform (traefik-net), not by anything this script sets up.
