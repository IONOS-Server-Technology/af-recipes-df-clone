#!/usr/bin/env bash
# install.sh — Install Jupyter Notebook via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: notebooks and working files.
mkdir -p /opt/jupyter-notebook/data
