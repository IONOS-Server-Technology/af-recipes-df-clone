#!/usr/bin/env bash
# install.sh — Install Jotty via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: notes, checklists, and Kanban boards (file-based, no database).
mkdir -p /opt/jotty/data
