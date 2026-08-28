#!/usr/bin/env bash
# install.sh — Install NATS via docker-compose
set -euo pipefail

set -a
source .env
set +a

mkdir -p /opt/nats/config
mkdir -p /opt/nats/data

# Write the NATS server config. NATS supports bcrypt hashes in the password field;
# the platform generates NATS_PASSWORD as bcrypt(ROOT_PASSWORD). Clients connect
# with nats://nats:ROOT_PASSWORD@host:4222 — NATS verifies the plaintext against
# the stored hash. The username "nats" is fixed (not parameterised) because only
# the password is a per-installation secret.
cat > /opt/nats/config/nats.conf << EOF
jetstream {
  store_dir: /data/jetstream
}

authorization {
  user: nats
  password: "$NATS_PASSWORD"
}

http: 8222
EOF
