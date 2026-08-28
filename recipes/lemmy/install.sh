#!/usr/bin/env bash
# install.sh — Install Lemmy via docker-compose
set -euo pipefail

# Generate this server's own secrets into .env before anything reads it. They ship
# empty in the delivered file — a fixed value here would be the same secret on every server.
#
# Idempotent on purpose: an existing non-empty value is left alone, so a re-run does not
# invalidate data already written under the old value.
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
af_gen_secret PICTRS_API_KEY

# Load the app's configuration, now that it is complete.
set -a
source .env
set +a

mkdir -p /opt/lemmy/config
mkdir -p /opt/lemmy/nginx
mkdir -p /opt/lemmy/pictrs
mkdir -p /opt/lemmy/postgres

# Lemmy backend reads its full configuration from config.hjson.
# The database URI and pictrs API key contain secrets generated above.
cat > /opt/lemmy/config/config.hjson << EOF
{
  database: {
    uri: "postgresql://lemmy:${POSTGRES_PASSWORD}@postgres:5432/lemmy"
  }
  pictrs: {
    url: "http://pictrs:8080/"
    api_key: "${PICTRS_API_KEY}"
  }
}
EOF

# pictrs runs as UID 991 and must own its media storage directory.
chown -R 991:991 /opt/lemmy/pictrs

# nginx reverse-proxy config: routes API, ActivityPub, and image-proxy paths to the
# lemmy backend (port 8536), and all other requests to lemmy-ui (port 1234).
# Written as a static file — no shell variables needed inside.
cat > /opt/lemmy/nginx/default.conf << 'NGINX_CONF'
upstream lemmy {
    server lemmy:8536;
}
upstream lemmy-ui {
    server lemmy-ui:1234;
}

server {
    listen 80;
    server_name _;
    server_tokens off;

    gzip on;
    gzip_types text/css application/javascript image/svg+xml;
    gzip_min_length 1024;

    client_max_body_size 20M;

    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # API, image proxy, feeds, and ActivityPub discovery paths go to the backend.
    location ~ ^/(api|pictrs|feeds|nodeinfo|\.well-known) {
        proxy_pass http://lemmy;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # ActivityPub content negotiation and POST requests route to the backend;
    # everything else goes to lemmy-ui.
    location / {
        set $proxpass "http://lemmy-ui";
        if ($http_accept = "application/activity+json") {
            set $proxpass "http://lemmy";
        }
        if ($http_accept = "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\"") {
            set $proxpass "http://lemmy";
        }
        if ($request_method = POST) {
            set $proxpass "http://lemmy";
        }
        proxy_pass $proxpass;
        rewrite ^(.+)/+$ $1 permanent;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX_CONF
