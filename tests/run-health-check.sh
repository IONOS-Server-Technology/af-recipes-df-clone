#!/usr/bin/env bash
# Copy a recipe's health-check.sh to the test VM and run it there, so the
# check inspects Docker state and curls the app on the VM's own localhost.
# Runs on the CI runner. Same scp+ssh pattern as the auto-inject checks
# (tests/auto-inject/run-auto-inject-checks.sh).
# Usage: run-health-check.sh <SERVERIP> <SSH_KEY_PATH> <RECIPE_NAME>
set -euo pipefail

SERVERIP="$1"
SSH_KEY="$2"
RECIPE_NAME="$3"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY")

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HC="$REPO_ROOT/recipes/$RECIPE_NAME/health-check.sh"

if [ ! -f "$HC" ]; then
  echo "ERROR: health-check.sh not found for recipe '$RECIPE_NAME' ($HC)" >&2
  exit 1
fi

echo "[AF] Copying $RECIPE_NAME health-check.sh to VM $SERVERIP"
scp "${SSH_OPTS[@]}" "$HC" "root@${SERVERIP}:/tmp/af-hc-${RECIPE_NAME}.sh"

# No URL arg -> the script runs in Docker-CI mode (waits for the container's
# docker healthcheck to report healthy).
echo "[AF] Running $RECIPE_NAME health-check.sh on VM"
ssh "${SSH_OPTS[@]}" "root@${SERVERIP}" "bash /tmp/af-hc-${RECIPE_NAME}.sh"
