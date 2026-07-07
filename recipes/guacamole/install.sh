#!/usr/bin/env bash
# install.sh — Install Apache Guacamole via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/guacamole/postgres
mkdir -p /opt/guacamole/init

# Generate database initialization script
docker run --rm guacamole/guacamole:1.5.5 /opt/guacamole/bin/initdb.sh --postgresql > /opt/guacamole/init/initdb.sql
