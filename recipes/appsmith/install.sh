#!/usr/bin/env bash
# install.sh — Install Appsmith via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: Appsmith's configuration, databases, and uploaded files.
mkdir -p /opt/appsmith/stacks
