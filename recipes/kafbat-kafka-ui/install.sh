#!/usr/bin/env bash
# install.sh — Install Kafbat Kafka UI via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/kafbat-kafka-ui/config
