# Anatomy of a recipe — annotated walk-through using `recipes/n8n/`

Each recipe lives in `recipes/<slug>/` and ships **five files** for `docker-compose` recipes (three for `native`). The slug must match `metadata.yaml`'s `id` field and the directory name.

## File 1: `metadata.yaml` — the contract

The schema-validated declaration of what the app is, what it costs, what it exposes, and what the customer has to provide. The AF API loads this at startup; if it doesn't validate, the API refuses to start.

Annotated `recipes/n8n/metadata.yaml`:

```yaml
id: n8n                           # slug — matches the directory name
display_name: n8n                 # what shows up in the customer's control panel
description: Low-code workflow automation tool to connect various apps and APIs.
categories:                       # one or more from the enum in metadata.schema.json
  - automation

app_version: "1.94.1"             # Whatever upstream uses — a pinned release here, or "latest"/"stable"
                                  # when upstream floats the tag (RFC-001 §6). Quote it; YAML may
                                  # parse 1.94 as a float otherwise.
recipe_version: "1.0.0"           # semver. Bump when this recipe changes (separate from app version)
recipe_type: docker-compose       # or 'native'
upstream_url: https://github.com/n8n-io/n8n

# Where this recipe's docker-compose.yaml was adapted from (RFC-001 §4.7).
# Direct file link, not the docs page. `null` when upstream ships none — say why in the notes.
compose_file_url: https://github.com/n8n-io/n8n-hosting/blob/main/docker-compose/withPostgres/docker-compose.yml
compose_file_notes: >-
  withPostgres variant. Rolling default-branch link — upstream tags no version of it.
  Upstream pins postgres:16 and floats n8n via N8N_VERSION (`stable`); this recipe
  does the same, per image.

app_min_ram_mb: 2048              # APP-ONLY. OS baseline (512 MB on ubuntu-26.04) is added once by the AF API.
app_min_disk_mb: 20480            # Same logic. CPU is OS-baseline only — don't declare per-app.

ports:                            # Network ports the *app declares*. Public ones are reachable from the internet.
  - port: 5678
    protocol: tcp
    public: true
    description: n8n Web UI

parameters:                       # Customer-facing inputs. UPPER_SNAKE_CASE names.
  - name: N8N_ADMIN_EMAIL
    display_name: Admin Email
    type: email
    required: true
    description: Email address for the n8n admin account.

  - name: POSTGRES_PASSWORD
    display_name: Database Password
    type: password
    required: false
    auto_generate: true           # AF API generates a 32-char secret if the customer doesn't supply one
    description: PostgreSQL database password (auto-generated if not provided).

  - name: N8N_ENCRYPTION_KEY
    display_name: Encryption Key
    type: password
    required: false
    auto_generate: true
    description: Key used to encrypt credentials stored in n8n (auto-generated if not provided).

incompatible_with_apps: []        # Other slugs that must not be co-installed. Empty for n8n.

preinstall_cmds:                  # Optional: shell snippets the cloud-init module runs before docker-compose up.
  - mkdir -p /opt/n8n/n8n
  - chown 1000:1000 /opt/n8n/n8n
```

## File 2: `docker-compose.yaml` — the runtime

Compose v3 (no `version:` key). Image tags mirror upstream's — pinned where it pins, floating where it floats (RFC-001 §6). Bind mounts under `/opt/<slug>/`. Healthchecks on every service. No public DB ports. One bridge network named `<slug>-network`. Environment from `${VAR}` references, never hardcoded.

Worth absorbing from `recipes/n8n/docker-compose.yaml`:

- Both services (`n8n`, `postgres`) have `restart: unless-stopped` — survives reboots without surviving manual stops.
- `postgres` has no `ports:` — it's only reachable on the internal `n8n-network`.
- `n8n.depends_on` waits for `postgres` to pass its healthcheck — avoids race conditions on first boot.
- Healthchecks use shell-form `CMD-SHELL` so we can use `||` for fallback.
- Volumes are absolute host paths (`/opt/n8n/n8n`, `/opt/n8n/postgres`) — these are pre-created in `preinstall_cmds` or `install.sh` to set ownership.

## File 3: `.env.template` — shipped verbatim, no placeholders

The renderer copies this file to the VM's `.env` byte for byte — there is no render-time
substitution (IF-944), so `{{PLACEHOLDER}}` tokens are forbidden outright
(`no-env-placeholder`, rfc/002-recipe-rules.md), not just required to match a parameter.
Every key is one of: a static literal, an empty key the recipe's own `install.sh` fills
with a per-VM secret on first boot, or an empty key the customer fills in themselves. The
app's own FQDN is never declared here — reference it in `docker-compose.yaml` as
`${AF_APP_DOMAIN}`, the platform's reserved key, written into `.env` at render time.

Example shape (`recipes/n8n/.env.template`):

```
# Secrets are generated per VM by install.sh on first boot and written back here.
# They ship empty on purpose: nothing substitutes values into this file (IF-944), so a
# literal committed here would be the same secret on every customer VM.
POSTGRES_PASSWORD=
N8N_ENCRYPTION_KEY=
TZ=UTC
```

`compose-var-defined-in-env` fails if `docker-compose.yaml` references a `${VAR}` that is
neither a `VAR=` line here nor a reserved platform key.

## File 4: `install.sh` — the runtime entry

Runs on the customer VM during cloud-init. Loads the resolved `.env`, ensures Docker is present, creates host directories, runs `docker-compose up -d`, and waits for the app to come healthy (typically 60s timeout).

Conventions:

- `set -euo pipefail` — fail loud on any error
- Source `.env` with `set -a` so the variables export to the compose subshell
- Create `/opt/<slug>/<service>/` directories with the correct ownership *before* compose up (containers fail with EACCES otherwise — see the n8n UID 1000 chown for the canonical example)
- Exit 0 only after a healthcheck against the app's primary port succeeds. Exit non-zero on timeout.

## File 5: `health-check.sh` — the CI test hook

CI-only. Not deployed to the customer VM. Receives the app's primary URL as `$1`. Exit 0 = healthy. Used by the WP3 testing pipeline to verify a freshly installed VM actually serves the app.

Minimal example:

```bash
#!/usr/bin/env bash
set -euo pipefail
URL="${1:?Usage: health-check.sh <url>}"
curl -fsS --max-time 10 "$URL" > /dev/null
```

## What's NOT in a recipe

- No Kubernetes manifests, Helm charts, or operator definitions — AF runs Docker Compose on a customer VPS, not K8s.
- No backup scripts — explicitly out of scope for AF Phase 1 (Q13 in the Question Catalogue).
- No update logic — updates are customer-initiated via WUD (What's Up Docker), notify-only. The recipe doesn't need to know about WUD; WUD is injected by the AF orchestrator at install time.
- No reverse-proxy config — Traefik handles that; the recipe just declares which ports are public.

## Adding a new recipe — directory checklist

```
recipes/<slug>/
├── metadata.yaml           ✅ schema-valid, version as upstream has it, params match .env.template
├── docker-compose.yaml     ✅ tags as upstream has them, healthchecks, bind mounts under /opt/<slug>/
├── .env.template           ✅ every {{PLACEHOLDER}} matches a param name in metadata.yaml
├── install.sh              ✅ executable bit, set -euo pipefail, waits for healthcheck
└── health-check.sh         ✅ executable bit, takes $1 = URL, exits 0 on healthy
```

Don't forget `chmod +x install.sh health-check.sh` after writing them.
