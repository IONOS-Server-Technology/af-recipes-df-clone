#!/usr/bin/env bash
# install.sh — Install JupyterLab via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/jupyterlab/work
# The base-notebook image runs as jovyan (UID 1000, GID 100); pre-create the
# bind-mount directory with the right ownership so the container can write on
# first start without relying on the image's NB_UID chown pass.
chown -R 1000:100 /opt/jupyterlab/work
