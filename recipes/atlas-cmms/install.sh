#!/usr/bin/env bash
# install.sh — Install Atlas CMMS via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads them.
# They ship empty — a fixed value here would be identical on every server.
#
# Idempotent: an existing non-empty value is left alone so a re-run does not
# break a database or JWT sessions already initialised with the old value.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex from /dev/urandom: no openssl dependency, and no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret POSTGRES_PASSWORD
af_gen_secret JWT_SECRET_KEY
af_gen_secret MINIO_PASSWORD

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

# Persistent data directories.
mkdir -p /opt/atlas-cmms/postgres
mkdir -p /opt/atlas-cmms/minio
mkdir -p /opt/atlas-cmms/logo
mkdir -p /opt/atlas-cmms/config

# Write the nginx reverse proxy config that routes frontend, API, and MinIO
# through one public host. Mounted read-only into the nginx container.
# Idempotent: recreating this file is always safe — it contains no secrets.
cat > /opt/atlas-cmms/nginx.conf << 'NGINX_EOF'
upstream atlas_frontend {
    server frontend:3000;
}

upstream atlas_backend {
    server api:8080;
}

upstream atlas_minio {
    server minio:9000;
}

server {
    listen 80;
    server_name _;

    client_max_body_size 200M;

    location / {
        proxy_pass http://atlas_frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /api/ {
        proxy_pass http://atlas_backend/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location /storage/ {
        proxy_pass http://atlas_minio/;
        proxy_set_header Host minio:9000;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        client_max_body_size 500M;
    }
}
NGINX_EOF
