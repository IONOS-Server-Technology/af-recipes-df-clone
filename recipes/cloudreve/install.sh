#!/usr/bin/env bash
# install.sh — Install Cloudreve via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/cloudreve/conf
mkdir -p /opt/cloudreve/uploads
