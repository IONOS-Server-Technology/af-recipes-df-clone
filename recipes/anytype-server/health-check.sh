#!/usr/bin/env bash
set -euo pipefail
HOST="${1:-localhost}"
echo "Checking AnyType coordinator at ${HOST}:4830 ..."
nc -z "${HOST}" 4830
echo "AnyType Server is healthy."
