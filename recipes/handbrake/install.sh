#!/usr/bin/env bash
# install.sh — Install HandBrake via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: HandBrake config, media storage, watch folder (input), and output folder.
mkdir -p /opt/handbrake/config /opt/handbrake/storage /opt/handbrake/watch /opt/handbrake/output
