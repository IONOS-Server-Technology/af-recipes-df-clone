# Gap-analysis issue design (DRAFT — for review, not yet run)

Goal: run one dark-factory issue per candidate app in `new-app-candidates.csv`
(997 apps) against project 3 (`af-recipes-clone`). Each issue does research +
analysis only — no recipe files, no PR. Output is a single YAML file per app
at `apps-gaps/<slug>.yaml`, committed back by the worker.

## Why analysis-only, not `af-create-recipe`

`af-create-recipe`'s Phase 2 (Research) is reused for methodology — reading
upstream docs, picking a Docker image/tag, sizing the stack — but Phases 3-5
(Plan/Generate/Handover) are skipped entirely. We don't want 997 recipe
drafts; we want a triage report to decide which apps are worth a real
`af-create-recipe` pass later.

## Constraint that shapes the whole analysis: no customer-supplied parameters

Confirmed against `IF-1420` (root-password projection, `generated_from:
"<algo>:ROOT_PASSWORD"`, branch `feature/IF-1420-generated-from`) and
`IF-1312` (Traefik `basic_auth` toggle, branch `feature/IF-1312-basic-auth`),
both still unmerged but representing the actual MVP mechanism:

- `/compose` does not accept arbitrary customer-supplied values. There is no
  form field, no API param, nothing — the JWE bootstrap token only carries
  what af-api derives itself.
- The **only** supported per-customer secret is a hash of their existing
  server root password, projected one of two ways:
  - `generated_from: "argon2:ROOT_PASSWORD"` (or `bcrypt`) on a `type:
    password` metadata parameter — the app's own login (Vaultwarden's
    `ADMIN_TOKEN` is the shipping example).
  - Traefik `basic_auth: true` on the app's public port — gates an app with
    no login of its own behind HTTP basic auth (n8n, WUD, OpenClaw,
    Open WebUI, Immich use this).
- Everything else (external API keys, OAuth tokens, arbitrary admin
  usernames/passwords, third-party account credentials) has **no input
  channel today**. A recipe can still declare such a parameter in
  `metadata.yaml` for documentation purposes, but no customer value ever
  reaches it.

Practical test for "installable via our recipe mechanism today":

| App needs at first boot | Installable now? |
|---|---|
| Just a domain | yes |
| Domain + one admin login → project root password into it | yes (`generated_from`) |
| Domain + no login, but should be gated | yes (Traefik `basic_auth`) |
| Domain + a random secret nothing customer-facing reads (DB password, JWT signing key) | yes — generate anything patternless server-side, customer never needs it |
| Domain + an external API key/token the app can't function without | **no** — no channel for the customer to supply it |
| Domain + OAuth app registration / third-party account linking | **no** |
| Multiple independent customer-chosen logins | **no** — root-password projection only covers one |

## `apps-gaps/<slug>.yaml` schema

```yaml
slug: <from CSV>
name: <from CSV, display name>
source_description: <from CSV, Hostinger's description — verbatim>

upstream:
  url: <homepage or repo>
  repo_url: <github url if OSS>
  license: <SPDX id or free text>
  docker_image: <official image, or null if none>

version_health:
  latest_version: <tag/release>
  latest_release_date: <YYYY-MM-DD>
  release_cadence: active | slowing | sporadic | dormant
  eol_status: active | maintenance-only | archived | eol
  notes: <e.g. "repo archived 2025-11", "no release in 2 years but issues still triaged", "vendor announced EOL date">

catalogue_fit:
  categories: [<af category-like tags>]
  has_web_ui: true | false
  reverse_proxy_compatible: true | false  # single HTTP port, no extra raw ports needed, works fine behind Traefik on <slug>.<base_domain>
  overlaps_with: [<existing recipe slugs covering similar ground, [] if none>]
  differentiation: <1-3 sentences: what does this add beyond the current 24 recipes>
  usefulness: high | medium | low
  usefulness_rationale: <1-3 sentences>

installability:
  recipe_type_guess: docker-compose | native
  secrets_required_at_first_boot: [<list of env vars / setup-flow secrets the app needs>]
  secrets_expressible_today:
    - secret: <name>
      mechanism: generated_from_root_password | traefik_basic_auth | server_generated_no_customer_input | none_needed
    # omit entries for secrets that have NO expressible mechanism — list those in blocking_issues instead
  blocking_issues: [<concrete reasons this can't ship as a recipe today, [] if none>]
  installable_today: true | false
  recommendation: build_now | build_with_caveats | blocked_on_platform | not_recommended

summary: <2-4 sentence human-readable verdict tying the above together>
```

Notes on the schema:
- `secrets_expressible_today` lists only what *can* be handled; anything the
  app needs that has no mechanism goes in `blocking_issues` — keeps the
  "why not" reasoning explicit instead of implied by absence.
- `installable_today` is the sharp yes/no; `recommendation` adds the softer
  judgment call (e.g. `build_with_caveats` for an app that's installable but
  low-value, or `blocked_on_platform` for one that's high-value but needs
  IF-1420/1312 merged, or a real API-key input channel, first).
- No `analyzed_at`/worker metadata field — dark-factory's own issue/job
  records already carry that provenance; don't duplicate it in-file.

## Shared issue stub (identical across all 997 issues)

```
Title: Gap analysis: <name>

Research and analyze the self-hosted app "<name>" (Hostinger catalogue slug
`<slug>`) as a candidate for the IONOS Application Factory recipe catalogue.
This is analysis only — do NOT create recipe files, do NOT open a PR.

Hostinger's description: "<source_description>"

## What to do

1. Read `.claude/skills/af-create-recipe/SKILL.md`, Phase 2 (Research) only,
   for the research method — upstream docs, official Docker image + pinned
   tag, ports, what the app needs to boot. Ignore Phases 1 and 3-5; this is
   not a recipe-authoring task.
2. Also check 2-3 structurally similar existing recipes under `recipes/` (see
   Phase 2's heuristics for picking similar recipes) to judge overlap and
   whether this app is reverse-proxy-compatible the way our recipes are.
3. Research version history: latest release, release cadence, and whether
   the project is active, in maintenance-only mode, archived, or explicitly
   EOL.
4. Evaluate fit against our current 24-recipe catalogue: does it duplicate
   something we already have, and if not, why would a customer want it?
   Note whether it has a web UI (preferred — we already have Traefik ready
   to front one) vs. requiring raw ports/protocols.
5. Evaluate installability under the CURRENT recipe mechanism constraint:
   `/compose` does not accept any customer-supplied value. The only
   supported per-customer secret is a hash of the customer's own root
   (server) password, projected via either `generated_from:
   "<algo>:ROOT_PASSWORD"` on the app's own admin-login parameter, or a
   Traefik `basic_auth: true` gate in front of an app with no login of its
   own. Anything the app needs beyond that (an external API key, OAuth
   registration, an arbitrary customer-chosen credential) has no input
   channel today and blocks `installable_today`.
6. Write your findings to `apps-gaps/<slug>.yaml` following the schema
   documented in `apps-gaps/SCHEMA.md`. [<- ships once, read-only reference]

Commit the new file only — no recipe files, no other changes.
```

Open questions before generating 997 of these:

1. Where should `apps-gaps/SCHEMA.md` (the schema reference above) live —
   committed to `af-recipes-clone` directly by us before dispatching any
   issues, so every worker can read it? (Recommended — avoids repeating the
   full schema in all 997 issue bodies.)
2. Batch size / pacing: dispatch all 997 at once, or in batches to watch a
   sample for quality first?
3. Do you want `project_id: 3` (af-recipes-clone) confirmed as the target for
   all of these, same as the recipe-creation work?
