#!/usr/bin/env bash
# install.sh — prep for What's Up Docker (auto-injected composition app).
# Prep-only per IF-1139: the shared compose-up.sh brings the stack up afterwards.
set -euo pipefail

# Persistent WUD state (watch history, review status). Host volume per Q61.
mkdir -p /opt/wud/store

# NOTE (IF-808): no auth is configured here yet. WUD's route is currently
# unauthenticated; the Traefik basic-auth feature (first-public-port opt-in) will
# own credentials once implemented. The old APR1-in-WUD flow was removed because
# af-core no longer substitutes {{PARAM}} placeholders and auth is moving to Traefik.
# traefik-net is created by the renderer's Traefik bootstrap block, not here.
