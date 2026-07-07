#!/usr/bin/env bash
# install.sh — Install Gitea via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/gitea/data
mkdir -p /opt/gitea/postgres
