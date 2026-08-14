#!/usr/bin/env bash
# install.sh — prepare What's Up Docker.
# Preparation only; the shared compose-up.sh helper starts the stack afterwards.
set -euo pipefail

# Persistent state (watch history, update status), kept on a host volume so it
# survives container restarts.
mkdir -p /opt/wud/store

# This application does not configure its own login. Access is controlled by the
# reverse proxy in front of it — see `auth.sh` on this server. The shared
# traefik-net network is created during setup, not here.
