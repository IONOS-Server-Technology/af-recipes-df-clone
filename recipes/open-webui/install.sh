#!/usr/bin/env bash
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Create host directories for persistent data
mkdir -p /opt/open-webui/data
mkdir -p /opt/open-webui/ollama
