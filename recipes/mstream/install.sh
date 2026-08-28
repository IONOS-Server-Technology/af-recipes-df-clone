#!/usr/bin/env bash
# install.sh — Install mStream via docker-compose
set -euo pipefail

# /config — mStream configuration (settings, users, database)
# /music  — bind-mount your music library here before first boot
mkdir -p /opt/mstream/config
mkdir -p /opt/mstream/music
