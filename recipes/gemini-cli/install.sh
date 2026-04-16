#!/usr/bin/env bash
# install.sh — Install Gemini CLI on bare-metal
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

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
