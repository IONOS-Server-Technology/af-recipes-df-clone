#!/usr/bin/env bash
set -euo pipefail

# Generate server-side secrets into .env before containers start. Values ship
# empty so no two servers share credentials. Idempotent: existing non-empty
# values are left alone so a re-run does not rotate secrets already in use.
af_gen_secret() {
    local key="$1" value
    if [ -n "$(sed -n "s/^${key}=//p" .env | head -1)" ]; then
        return 0
    fi
    # Hex out of /dev/urandom: no openssl dependency, no '$' for Compose to
    # interpolate away when it reads this .env.
    value="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >>.env
    fi
}

af_gen_secret DB_PASSWORD
af_gen_secret DB_ROOT_PASSWORD
af_gen_secret JWT_SECRET

set -a
source .env
set +a

mkdir -p /opt/bigcapital/mysql
mkdir -p /opt/bigcapital/redis
mkdir -p /opt/bigcapital/envoy
mkdir -p /opt/bigcapital/mariadb-init

# Envoy config: routes /api/* to the server container and /* to the webapp.
# The admin listener (9901) is used only for the Docker healthcheck — it binds
# to loopback and is never exposed outside the container.
cat > /opt/bigcapital/envoy/envoy.yaml << 'ENVOY_YAML'
admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 9901

static_resources:
  listeners:
    - name: listener_0
      address:
        socket_address:
          address: 0.0.0.0
          port_value: 80
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                '@type': type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: ingress_http
                route_config:
                  name: local_route
                  virtual_hosts:
                    - name: backend
                      domains: ['*']
                      routes:
                        - match:
                            prefix: '/api'
                          route:
                            cluster: dynamic_server
                        - match:
                            prefix: '/'
                          route:
                            cluster: webapp
                http_filters:
                  - name: envoy.filters.http.router
                    typed_config:
                      '@type': type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
    - name: dynamic_server
      connect_timeout: 0.25s
      type: STRICT_DNS
      dns_lookup_family: V4_ONLY
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: dynamic_server
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: server
                      port_value: 3000

    - name: webapp
      connect_timeout: 0.25s
      type: STRICT_DNS
      dns_lookup_family: V4_ONLY
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: webapp
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: webapp
                      port_value: 80
ENVOY_YAML

# MariaDB init: grants the bigcapital user full cross-database access so the
# server can create and migrate per-tenant databases at runtime (the standard
# GRANT for MYSQL_USER/MYSQL_DATABASE only covers that single named database).
cat > /opt/bigcapital/mariadb-init/00-grants.sql << EOF
GRANT ALL PRIVILEGES ON *.* TO 'bigcapital'@'%' IDENTIFIED BY '${DB_PASSWORD}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
