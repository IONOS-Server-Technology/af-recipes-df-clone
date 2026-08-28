#!/usr/bin/env bash
# install.sh — Install MediaGo via docker-compose
set -euo pipefail

# Persistent storage: downloaded video files.
mkdir -p /opt/mediago/downloads
