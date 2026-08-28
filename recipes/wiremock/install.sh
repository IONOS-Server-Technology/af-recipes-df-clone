#!/usr/bin/env bash
# install.sh — Install WireMock via docker-compose
set -euo pipefail

# Persistent stub mappings and response files, kept on host volumes so they
# survive container restarts and image updates.
mkdir -p /opt/wiremock/mappings
mkdir -p /opt/wiremock/files
