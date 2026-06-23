#!/usr/bin/env bash
# Health checks for docker_auto_inject:true recipes on a test VM via SSH.
# Usage: run-auto-inject-checks.sh <SERVERIP> <SSH_KEY_PATH>
set -euo pipefail

SERVERIP="$1"
SSH_KEY="$2"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY")

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Guard: auto-inject recipes are only injected into docker-compose VMs.
# Skip this check if the carrier recipe is not docker-compose.
if [ -n "${RECIPE_NAME:-}" ]; then
  _meta="$REPO_ROOT/recipes/$RECIPE_NAME/metadata.yaml"
  if [ -f "$_meta" ]; then
    _type=$(grep '^recipe_type:' "$_meta" | awk '{print $2}')
    if [ "$_type" != "docker-compose" ]; then
      echo "[AF] Skipping auto-inject checks: carrier recipe '$RECIPE_NAME' is not docker-compose (type: $_type)"
      exit 0
    fi
  fi
fi

found=0
failed=0
for metadata in "$REPO_ROOT"/recipes/*/metadata.yaml; do
  [ -f "$metadata" ] || continue
  grep -q '^docker_auto_inject:[[:space:]]*true' "$metadata" 2>/dev/null || continue

  recipe_id=$(grep '^id:' "$metadata" | awk '{print $2}')
  found=$((found + 1))

  echo "[AF] Checking auto-inject recipe: $recipe_id"

  # 1. Assert container is running on the VM
  if ! ssh "${SSH_OPTS[@]}" root@"$SERVERIP" \
      "docker ps --filter 'name=${recipe_id}' --format '{{.Names}}' | grep -q ."; then
    echo "ERROR: No container matching '${recipe_id}' running on VM" >&2
    failed=$((failed + 1))
    continue
  fi

  # 2. Copy health-check.sh to VM and run it there (Docker-CI mode, no URL arg)
  if ! scp "${SSH_OPTS[@]}" "$REPO_ROOT/recipes/$recipe_id/health-check.sh" \
         root@"$SERVERIP":/tmp/af-hc-${recipe_id}.sh; then
    echo "ERROR: Failed to copy health-check.sh for $recipe_id to VM" >&2
    failed=$((failed + 1))
    continue
  fi
  if ! ssh "${SSH_OPTS[@]}" root@"$SERVERIP" "bash /tmp/af-hc-${recipe_id}.sh"; then
    echo "ERROR: health-check.sh failed for $recipe_id" >&2
    failed=$((failed + 1))
  else
    echo "[AF] $recipe_id: HEALTHY"
  fi
done

if [ "$found" -eq 0 ]; then
  echo "ERROR: No docker_auto_inject recipes found — test coverage gap!" >&2
  exit 1
fi

if [ "$failed" -gt 0 ]; then
  echo "ERROR: $failed/$found auto-inject recipe(s) failed" >&2
  exit 1
fi

echo "[AF] All auto-inject recipes passed ($found checked)"
