#!/usr/bin/env bash
# install.sh — Install Claude Code on bare-metal
set -euo pipefail

# No `source .env` here: this is a recipe_type: native recipe, and the renderer ships only
# install.sh for those — the .env write lives in the docker-compose branch. Sourcing a file
# that is never delivered aborted this script under `set -euo pipefail`, and because the
# top-level installer runs each app as `( cd /opt/<app> && bash install.sh )` under the same
# flags, that took the whole bootstrap down with it: every app after this one uninstalled,
# and cc_application_factory's failure marker leaves the VM quarantined with SSH locked.
# Latent only because both native recipes are enabled: false — and the live test workflow
# filters on `enabled`, not on recipe_type, so it would have fired on the first run after
# anyone flipped that flag.

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
