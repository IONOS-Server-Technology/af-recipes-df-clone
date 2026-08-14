#!/usr/bin/env bash
# install.sh — Install Gemini CLI on bare-metal
set -euo pipefail

# No `source .env` here: this application is installed directly on the server rather than
# in a container, and no .env file is delivered for it. Sourcing a file that does not
# exist would abort this script under `set -euo pipefail`.
#
# GEMINI_API_KEY below tolerates being unset for the same reason — set it yourself after
# the installation.

# Install system dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y curl python3 python3-pip

# Install Gemini CLI via pip
echo "Installing Gemini CLI..."
pip3 install google-generativeai

# Configure API key if provided
if [ -n "${GEMINI_API_KEY:-}" ]; then
  echo "Configuring Gemini API key..."
  mkdir -p ~/.config/gemini
  echo "api_key: $GEMINI_API_KEY" > ~/.config/gemini/config.yaml
  chmod 600 ~/.config/gemini/config.yaml
fi

# Verify installation
echo "Verifying installation..."
python3 -c "import google.generativeai as genai; print('Gemini CLI installed successfully')" || {
  echo "Installation verification failed"
  exit 1
}

exit 0
