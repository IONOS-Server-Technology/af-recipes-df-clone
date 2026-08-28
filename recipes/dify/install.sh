#!/usr/bin/env bash
# install.sh — Install Dify via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone, so a re-run does not
# invalidate data already written under the old value (e.g. rotating SECRET_KEY would
# invalidate all existing Dify sessions and encrypted stored credentials).
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex out of /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret POSTGRES_PASSWORD
af_gen_secret REDIS_PASSWORD
af_gen_secret SECRET_KEY
af_gen_secret SANDBOX_API_KEY
af_gen_secret PLUGIN_DAEMON_KEY
af_gen_secret INNER_API_KEY_FOR_PLUGIN

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories for persistent data.
mkdir -p /opt/dify/api/storage
mkdir -p /opt/dify/postgres
mkdir -p /opt/dify/redis
mkdir -p /opt/dify/sandbox/dependencies
mkdir -p /opt/dify/plugin-daemon/storage
mkdir -p /opt/dify/nginx

# Write the nginx reverse-proxy config that routes the single public port (80)
# to the two Dify services: api (port 5001) and web (port 3000).
# This file is bind-mounted read-only into the nginx container at /etc/nginx/conf.d/.
cat > /opt/dify/nginx/default.conf << 'NGINX_CONF'
server {
    listen 80;
    server_name _;
    client_max_body_size 100M;

    # Dify console and public API paths — all handled by the api container
    location /console/api {
        proxy_pass http://api:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location /api {
        proxy_pass http://api:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location /v1 {
        proxy_pass http://api:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location /files {
        proxy_pass http://api:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # WebSocket endpoint for streaming AI responses
    location /socket.io/ {
        proxy_pass http://api:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 3600s;
    }

    # Dify web frontend (Next.js, port 3000)
    location / {
        proxy_pass http://web:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
NGINX_CONF
