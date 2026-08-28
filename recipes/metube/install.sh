#!/usr/bin/env bash
# install.sh — Install MeTube via docker-compose
set -euo pipefail

# Persistent storage: downloaded video and audio files.
mkdir -p /opt/metube/downloads
