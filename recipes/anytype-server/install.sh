#!/usr/bin/env bash
# install.sh — Install AnyType Server via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/anytype-server/coordinator
mkdir -p /opt/anytype-server/filenode
mkdir -p /opt/anytype-server/node
mkdir -p /opt/anytype-server/mongo
mkdir -p /opt/anytype-server/minio
