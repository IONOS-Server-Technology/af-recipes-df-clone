#!/usr/bin/env bash
# install.sh — Install What's Up Docker (composition app) via docker-compose
set -euo pipefail

set -a
source .env
set +a

command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }
command -v openssl >/dev/null || { echo "Error: openssl not found (needed for APR1 hash)"; exit 1; }

[ -n "${BASE_DOMAIN:-}" ] || { echo "Error: BASE_DOMAIN is required but not set"; exit 1; }

# Passwords containing ':' break HTTP Basic auth credential encoding.
case "${WUD_ADMIN_PASSWORD:-}" in
  *:*) echo "Error: WUD_ADMIN_PASSWORD must not contain ':'"; exit 1 ;;
esac

mkdir -p /opt/wud/store

# traefik-net is the external bridge shared with Traefik. In production af-core
# ensures it exists before deploying any recipe. The 2>/dev/null || true form
# is idempotent under parallel composition-app installs (both may pass inspect
# and race on create — create is a no-op if the network already exists).
docker network create traefik-net 2>/dev/null || true

# Generate an APR1 htpasswd hash and write auth vars to .env.
# APR1 hashes contain literal '$' characters. Docker Compose (v1 / docker-compose)
# interpolates '$' in env_file values, so each '$' must be doubled to '$$' so
# that Compose passes the literal '$apr1$…' string to the container.
# This was validated end-to-end in the IF-675 PoC (§2.5e) with docker-compose v2.
# If running with 'docker compose' (compose plugin v2.x), env_file values are
# passed verbatim — verify with 'docker compose config' post-install if auth fails.
if ! grep -q 'WUD_AUTH_BASIC_ADMIN_USER' .env 2>/dev/null; then
  HASH=$(openssl passwd -apr1 "${WUD_ADMIN_PASSWORD}")
  ESCAPED_HASH=$(printf '%s' "$HASH" | sed 's/\$/\$\$/g')
  {
    echo ""
    echo "# Auth vars written by install.sh — do not edit manually"
    echo "WUD_AUTH_BASIC_ADMIN_USER=admin"
    echo "WUD_AUTH_BASIC_ADMIN_HASH=${ESCAPED_HASH}"
  } >> .env
fi

# Restrict .env permissions: it contains the admin password in plaintext.
chmod 600 .env

docker-compose up -d

# Wait up to 60 s. WUD has no published host port (routes via Traefik), so probe
# via docker-compose exec to stay inside the container network.
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
  HTTP_CODE=$(docker-compose exec -T wud \
    curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
    http://127.0.0.1:3000/api/registries 2>/dev/null || echo "000")
  if echo "$HTTP_CODE" | grep -qE '^(200|401)$'; then
    echo "WUD is healthy (HTTP ${HTTP_CODE})"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: WUD failed to become healthy after ${max_attempts}s"
exit 1
