#!/usr/bin/env bash
# install.sh — Install LMS via docker-compose
set -euo pipefail

# Persistent data: LMS config, SQLite database, and cache.
mkdir -p /opt/lms/data

# Music library mount point. The customer populates this directory (or replaces
# the bind-mount path in docker-compose.yaml) with their actual music library
# before or after the initial deploy.
mkdir -p /opt/lms/music
