#!/usr/bin/env bash
# install.sh — Install FUXA via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: SQLite database, logs, uploaded images, projects, and exports.
mkdir -p /opt/fuxa/db
mkdir -p /opt/fuxa/logs
mkdir -p /opt/fuxa/images
mkdir -p /opt/fuxa/projects
mkdir -p /opt/fuxa/export
