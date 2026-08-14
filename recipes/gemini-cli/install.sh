#!/usr/bin/env bash
# install.sh — Install Gemini CLI on bare-metal
set -euo pipefail

# No `source .env` here — see the same note in recipes/claude-code/install.sh. Short version:
# native recipes get only install.sh from the renderer, so sourcing .env aborted this script
# and, through the top-level `( cd ... && bash install.sh )`, the entire bootstrap.
#
# GEMINI_API_KEY below is already written to tolerate being unset, which is the right shape
# for a native recipe: there is no .env to carry it, so the customer sets it post-install.

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
