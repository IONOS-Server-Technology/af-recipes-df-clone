# Draft 2 of 2

## Summary
AF - Populate upstream compose metadata and resync existing recipes to
upstream's current versions/structure

## Description
Depends on IF-1500. For each of the 22 docker-compose recipes: find the
upstream compose source, record `compose_file_url`/`compose_file_notes`,
and update the recipe to match upstream's current file — same research,
one pass.

**Versions: adopt upstream's choice as-is, including floating tags.**
If upstream floats (e.g. n8n's `${N8N_VERSION:-stable}`), we float too —
don't resolve it to a pin. Upstream has the direct incentive/information
to keep their own file valid; our own `test-recipes-live` pass is the
safety net, not a pin. Immich floats its app images while digest-pinning
Postgres/Valkey — adopting that wholesale also resolves IF-1422's
Postgres-pairing blocker for free.

**Also check structural drift, not just versions.** openclaw vs. its
real upstream file: missing ports (18790, 3978), missing security
hardening (`cap_drop`, `no-new-privileges`), stale healthcheck. Check all
22, not just openclaw.

**Unchanged**: our `/opt/<slug>/` paths, WUD labels, network setup,
secret wiring — deliberate, not drift.

## Acceptance Criteria
- Per recipe: record `compose_file_url`/`compose_file_notes`; match image
  versions to upstream (pin-or-float, matching upstream); apply real
  structural drift, adapted to our conventions.
- Passes `test-recipes-live.yaml` before merge.
- One PR per recipe (22 total), each documenting what changed and why.
