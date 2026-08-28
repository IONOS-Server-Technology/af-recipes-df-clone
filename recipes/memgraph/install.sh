#!/usr/bin/env bash
# install.sh — Install Memgraph via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Persistent data: Memgraph graph database files stored in /var/lib/memgraph
# inside the container, bind-mounted here for backup and migration tooling.
mkdir -p /opt/memgraph/data
