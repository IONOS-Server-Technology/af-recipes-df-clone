#!/usr/bin/env bash
# install.sh — Install Unstructured via docker-compose
set -euo pipefail

set -a
source .env
set +a

# Unstructured is a stateless container; no persistent directories are needed.
