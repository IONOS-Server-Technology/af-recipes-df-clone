#!/usr/bin/env bash
# install.sh — Install OwnTracks Recorder via docker-compose
set -euo pipefail

# Create the data directory for location history before Compose starts.
mkdir -p /opt/owntracks-recorder/store
