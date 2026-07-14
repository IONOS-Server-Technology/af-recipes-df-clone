#!/usr/bin/env bash
# install.sh — Install Pi-hole via docker-compose (WireGuard-only mode)
set -euo pipefail

set -a
source .env
set +a

WG_INTERFACE_IP="${WG_INTERFACE_IP:-10.8.0.1}"

# WireGuard must be running before Pi-hole can bind to its interface
if ! ip link show wg0 > /dev/null 2>&1; then
  echo "Error: WireGuard interface wg0 not found."
  echo "Please install and start wg-easy before installing Pi-hole."
  exit 1
fi
if ! ip addr show wg0 | grep -qF "${WG_INTERFACE_IP}"; then
  echo "Error: ${WG_INTERFACE_IP} is not assigned to wg0."
  echo "Check your WireGuard subnet or set WG_INTERFACE_IP in .env accordingly."
  exit 1
fi

mkdir -p /opt/pihole/etc-pihole
mkdir -p /opt/pihole/etc-dnsmasq.d

echo ""
echo "================================================================"
echo " Pi-hole is starting up."
echo ""
echo " Connect to WireGuard VPN, then:"
echo "   Admin UI : http://${WG_INTERFACE_IP}:8080/admin/"
echo "   DNS      : set your DNS to ${WG_INTERFACE_IP} in your"
echo "              WireGuard peer config (DNS = ${WG_INTERFACE_IP})"
echo "================================================================"
echo ""
