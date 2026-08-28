#!/usr/bin/env bash
# install.sh — Install Audiobookshelf via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/audiobookshelf/audiobooks
mkdir -p /opt/audiobookshelf/podcasts
mkdir -p /opt/audiobookshelf/metadata
mkdir -p /opt/audiobookshelf/config
