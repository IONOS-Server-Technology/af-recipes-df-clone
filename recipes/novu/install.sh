#!/usr/bin/env bash
# install.sh — Install Novu via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone. Rotating
# JWT_SECRET or STORE_ENCRYPTION_KEY on a re-run would invalidate all existing
# sessions and encrypted credentials.
af_gen_secret() {
    local key="$1" nbytes="${2:-32}" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex out of /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N"${nbytes}" /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >> .env
    fi
}

# JWT_SECRET and NOVU_SECRET_KEY: 64-char hex (32 bytes)
af_gen_secret JWT_SECRET 32
af_gen_secret NOVU_SECRET_KEY 32

# STORE_ENCRYPTION_KEY: Novu requires exactly 32 characters — 16 bytes as hex
af_gen_secret STORE_ENCRYPTION_KEY 16

# MongoDB root password: 64-char hex (32 bytes)
af_gen_secret MONGO_INITDB_ROOT_PASSWORD 32

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Create host directories for persistent data
mkdir -p /opt/novu/mongodb
mkdir -p /opt/novu/redis

# Write the nginx reverse proxy config that gates port 4000.
# Routing:
#   /api/       → api:3000  (strip /api prefix; browser uses VITE_API_HOSTNAME=/api)
#   /socket.io/ → ws:3002   (WebSocket upgrade for in-app notification channel)
#   /           → dashboard:4200
cat > /opt/novu/nginx.conf << 'NGINX_EOF'
server {
    listen 4000;
    server_name _;

    location /api/ {
        proxy_pass http://api:3000/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /socket.io/ {
        proxy_pass http://ws:3002/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
    }

    location / {
        proxy_pass http://dashboard:4200/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX_EOF
