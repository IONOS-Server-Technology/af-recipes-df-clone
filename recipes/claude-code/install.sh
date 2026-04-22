#!/usr/bin/env bash
# install.sh — Install Claude Code on bare-metal
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Install system dependencies
echo "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y curl git

# Download and install Claude Code
echo "Downloading Claude Code..."
RELEASE_URL=$(curl -fsS https://api.github.com/repos/anthropics/claude-code/releases/latest \
  | grep browser_download_url | grep "linux.*x64" | cut -d '"' -f 4 | head -1)

if [ -z "$RELEASE_URL" ]; then
  echo "Error: Could not find Claude Code release"
  exit 1
fi

curl -L "$RELEASE_URL" -o /tmp/claude-code.tar.gz

# Extract and install
echo "Installing Claude Code..."
sudo mkdir -p /opt/claude-code
sudo tar -xzf /tmp/claude-code.tar.gz -C /opt/claude-code --strip-components=1
sudo ln -sf /opt/claude-code/bin/claude-code /usr/local/bin/claude-code
rm /tmp/claude-code.tar.gz

# Verify installation
echo "Verifying installation..."
claude-code --version || { echo "Installation verification failed"; exit 1; }

echo "Claude Code installed successfully"
exit 0
