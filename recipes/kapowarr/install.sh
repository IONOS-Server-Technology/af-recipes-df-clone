#!/usr/bin/env bash
# install.sh — Install Kapowarr via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/kapowarr/db
mkdir -p /opt/kapowarr/temp_downloads
mkdir -p /opt/kapowarr/comics
