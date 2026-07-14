#!/usr/bin/env bash
# install.sh — Install AdGuard Home via docker-compose (WireGuard-only mode)
set -euo pipefail

set -a
source .env
set +a

WG_INTERFACE_IP="${WG_INTERFACE_IP:-10.8.0.1}"

# WireGuard must be running before AdGuard Home can bind to its interface
if ! ip link show wg0 > /dev/null 2>&1; then
  echo "Error: WireGuard interface wg0 not found."
  echo "Please install and start wg-easy before installing AdGuard Home."
  exit 1
fi
if ! ip addr show wg0 | grep -qF "${WG_INTERFACE_IP}"; then
  echo "Error: ${WG_INTERFACE_IP} is not assigned to wg0."
  echo "Check your WireGuard subnet or set WG_INTERFACE_IP in .env accordingly."
  exit 1
fi

mkdir -p /opt/adguard-home/work
mkdir -p /opt/adguard-home/conf

# Seed default config only on first install — preserves user settings on reinstall
if [ ! -f /opt/adguard-home/conf/AdGuardHome.yaml ]; then
  cp AdGuardHome.yaml /opt/adguard-home/conf/AdGuardHome.yaml
fi

echo ""
echo "================================================================"
echo " AdGuard Home is starting up."
echo ""
echo " Connect to WireGuard VPN, then:"
echo "   Admin UI : http://${WG_INTERFACE_IP}/admin/"
echo "   DNS      : set your DNS to ${WG_INTERFACE_IP} in your"
echo "              WireGuard peer config (DNS = ${WG_INTERFACE_IP})"
echo "================================================================"
echo ""
