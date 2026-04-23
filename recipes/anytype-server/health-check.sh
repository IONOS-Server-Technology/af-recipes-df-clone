#!/usr/bin/env bash
set -euo pipefail
HOST="${1:-127.0.0.1}"
echo "Checking AnyType coordinator at ${HOST}:4830 ..."
nc -z "${HOST}" 4830
echo "AnyType Server is healthy."
