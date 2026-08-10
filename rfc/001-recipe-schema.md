# RFC-001: Recipe Schema Specification

**Status:** Draft
**Author:** Oliver Knabe
**Date:** 2026-04-14
**Story:** IF-545 — WP1: Recipe Format & Catalogue Design

## 1. Overview

This document defines the standard recipe format for the Application Factory (AF). A recipe is a declarative description of an application — what it needs, how it's composed, and what parameters a customer must provide. Recipes are consumed by the AF API to generate installation payloads.

## 2. Recipe Types

| Type | Description | Required Files |
|---|---|---|
| `docker-compose` | Containerized application deployed via Docker Compose | `metadata.yaml`, `docker-compose.yaml`, `.env.template`, `install.sh`, `health-check.sh` |
| `native` | Application installed directly on the OS (no Docker) | `metadata.yaml`, `install.sh`, `health-check.sh` |

## 3. Directory Structure

```
af-recipes/
├── rfc/                          # Specifications
│   └── 001-recipe-schema.md
├── recipes/
│   ├── n8n/                      # One directory per application
│   │   ├── metadata.yaml
│   │   ├── docker-compose.yaml
│   │   ├── .env.template
│   │   ├── install.sh
│   │   └── health-check.sh
│   ├── claude-code/              # native example
│   │   ├── metadata.yaml
│   │   ├── install.sh
│   │   └── health-check.sh
│   └── .../
├── catalogue.json                # Generated index of all recipes
└── bin/
    └── build-catalogue           # Script to generate catalogue.json
```

## 4. metadata.yaml Specification

### 4.1 Top-Level Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Machine-readable slug (lowercase, hyphens). Must match directory name. |
| `enabled` | boolean | yes | Whether the recipe is exposed by the AF API. Disabled recipes stay in the catalogue source but are hidden from public endpoints. |
| `display_name` | string | yes | Human-readable name for UI display. |
| `description` | string | yes | One-line description of the application. |
| `short_description` | map[lang→string] | yes | Customer-facing short description as a language map. Keys are ISO 639-1 codes (`en` required, max 160 chars per value). The `en` key must always be present. Additional languages: `de`, `es`, `fr`, `it`, `nl`, `pl`. |
| `categories` | list[enum] | yes | Application categories, one or more (see §4.2). |
| `app_version` | string | yes | Upstream application version being deployed. |
| `recipe_version` | string | yes | Recipe format version (semver). |
| `recipe_type` | enum | yes | `docker-compose` or `native`. |
| `upstream_url` | string | yes | URL to the upstream project (GitHub, website). |
| `app_min_ram_mb` | integer | yes | Minimum RAM in MB required by the application (excluding OS/Docker overhead). |
| `app_min_disk_mb` | integer | yes | Minimum disk space in MB required by the application. |
| `ports` | list[port] | no | Network ports (see §4.3). |
| `parameters` | list[parameter] | no | Recipe-author documentation only — **no longer consumed at runtime** (IF-944). The API does not expose, accept, validate, or substitute them, and the `{{PARAM}}` placeholder mechanism has been removed (`.env.template` must contain literal values). Still shape-validated by `af-validate`. See §4.4. |
| `preinstall_cmds` | list[string] | no | Shell commands run before the recipe's compose/install step (e.g. `docker network create …`). |
| `docker_auto_inject` | boolean | no | If `true`, this recipe is **auto-injected** by af-core whenever the customer's selection includes at least one `recipe_type: docker-compose` recipe. Such recipes must themselves be `docker-compose`, must ship `enabled: false` (hidden from the catalogue), and are rejected by `POST /api/v1/compose` if selected directly. See §4.5. |
| `logo_url` | string | conditional | HTTPS URL to the logo served from the IONOS Object Storage bucket. Required for `enabled: true` recipes. See §4.6. |
| `logo_sha256` | string | conditional | SHA-256 (lowercase hex) of the logo file. Required when `logo_url` is set. |
| `logo_license` | string | conditional | License or usage basis (e.g. `CC-BY-SA-4.0`, `MIT`, `trademark-nominative-fair-use`). Required when `logo_url` is set. |
| `logo_source` | string | no | Attribution URL — the upstream page or repository the logo was sourced from. |

### 4.2 Categories

| Value | Description |
|---|---|
| `developer-tools` | IDEs, CLIs, coding assistants |
| `ai` | AI/ML models, agents, LLM tools |
| `automation` | Workflow automation, orchestration |
| `infrastructure` | Container management, reverse proxies |
| `communication` | Chat, messaging, collaboration |
| `database` | Database servers and management tools |
| `monitoring` | Observability, logging, uptime checking |
| `productivity` | Notes, project management, wikis |
| `security` | Password managers, auth tools, VPN |
| `media` | Media servers, streaming, file sharing |

### 4.3 Port Object

| Field | Type | Required | Description |
|---|---|---|---|
| `port` | integer | yes | Port number. |
| `protocol` | enum | yes | `tcp` or `udp`. |
| `public` | boolean | yes | Whether this port should be accessible externally. |
| `http` | boolean | no | Whether this is an HTTP(S) port routed through the per-VM Traefik reverse proxy (default `true`). HTTP ports are reached at `<app-id>.<base_domain>` and never bind the host, so they are exempt from the port-uniqueness rule. Set `false` for raw TCP/UDP services (SSH, WireGuard, sync protocols) that bind the host port directly. A `udp` port cannot be HTTP-routed, so `http` must be `false` for it. A raw port may not claim `80` or `443` — Traefik binds those. Declare at most one HTTP port per recipe: only the first gets a router. |
| `basic_auth` | boolean | no | Whether Traefik requires HTTP basic auth in front of this port (default `false`). See §4.3.1. |
| `description` | string | yes | What this port is for (e.g., "Web UI"). |

#### 4.3.1 `basic_auth` — protecting a frontend that has no login

Set `basic_auth: true` to put an HTTP basic-auth prompt in front of the app's frontend. At that
prompt the customer enters:

- **Username:** `admin` (fixed — not the recipe's name and not `root`)
- **Password:** their server password, i.e. the same one they use to log in to the VM

One shared credential protects every opted-in frontend on that VM. Traefik stores it as a
bcrypt hash; the password itself never reaches the recipe.

**Only for frontends without their own login** — dashboards, exporters, admin UIs. If the app
already authenticates its users, do not set this: the customer would face two prompts, and the
app's own accounts remain the real access control.

Constraints:

- **Traefik-routed ports only.** Basic auth is applied by the Traefik router, which only exists
  for a port that is `public`, `http` and `tcp`. Setting it on a raw or non-public port is an
  error (`basic-auth-requires-routed-port`) — that port has no router, so the flag would
  silently protect nothing.
- **One route per app.** As with `http`, the router covers the app's first Traefik-routed port,
  and auth applies to that whole router. There is no path-scoped auth and no per-app password.
- **A `base_domain` is required.** Without one there is no Traefik and no route, so a selection
  containing a basic-auth recipe is rejected at compose time rather than installed unprotected.
- **Router-wide, including inbound webhooks and OAuth callbacks.** Auth covers the entire
  router, so external callers hitting a callback path get a `401` too — exempting individual
  paths is not supported. This is a trade-off to weigh, not an automatic disqualifier: n8n
  carries the flag despite it (IF-1312), because the setup-takeover window it closes — anyone
  reaching the URL before the customer's first visit becomes the owner — was judged worse than
  breaking inbound webhooks until the customer runs `/root/auth.sh off <app>`. Recipe authors
  should state which way that trade-off falls for their app, the way the n8n and immich recipe
  comments do, rather than assume one answer.
- **Your `install.sh` must append to `.env`, never overwrite it.** The renderer writes the
  credential line into the app's `.env`; an `install.sh` that rewrites the file (`>` instead of
  `>>`, or regenerating it from a template) removes it. Traefik then fails closed — it rejects
  the middleware and the app's router stops serving, so the app returns `404` instead of going
  live unprotected — but the app is broken either way.

### 4.4 Parameter Object

> **Deprecated at runtime (IF-944).** Parameters are no longer consumed by the AF API
> or af-core — not exposed via `/catalogue`, not accepted by `/compose`. The block is
> retained only as recipe-author documentation and is shape-validated by `af-validate`;
> the `{{PARAM}}` placeholder mechanism has been removed for customer-supplied values.
> The fields below describe the original (pre-IF-944) design. **Exception:** `generated_from`
> (IF-1420) is API-computed rather than customer-supplied, so it is exempt from the
> removal — its hash is substituted into `.env`, reusing the `{{PARAM}}` placeholder
> where the template declares one.

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Machine-readable parameter name (UPPER_SNAKE_CASE). |
| `display_name` | string | yes | Human-readable label for UI. |
| `type` | enum | yes | `string`, `email`, `domain`, `password`, `boolean`, `integer`. |
| `default` | any | no | Default value if not provided. |
| `generated_from` | string | no | Derive this value from an existing secret, as `<algo>:<source>` (IF-1420). `<algo>` is `argon2` (always emits an argon2id PHC string) or `bcrypt`; `<source>` is `ROOT_PASSWORD`, the customer's server password. The hash is computed at compose time, so the plaintext never enters the bootstrap token. Only valid on `type: password`. |
| `description` | string | no | Help text for the customer. |
| `validation` | string | no | Regex pattern for validation. |

### 4.5 Auto-injected recipes (composition apps)

A recipe with `docker_auto_inject: true` is **auto-injected** by af-core onto every VM whose customer selection contains at least one `recipe_type: docker-compose` recipe. It is infrastructure the AF platform manages transparently — not a user-selectable application. (Such recipes are also referred to as *composition apps*.)

Rules (all enforced by `af-validate`, the renderer, or `/api/v1/compose`):
- **Must be disabled.** `docker_auto_inject: true` requires `enabled: false` — the recipe never appears in the customer-facing catalogue. `af-validate` enforces this (`auto-inject-must-be-disabled`).
- **Must be docker-compose.** Auto-inject recipes are themselves `recipe_type: docker-compose`; the renderer only injects recipes of that type.
- **Must ship an executable `health-check.sh`.** `af-validate` enforces this (`auto-inject-health-check-required`); the test pipeline runs it (see IF-940).
- **Conditional injection.** af-core injects auto-inject recipes **only when** the customer's selection (excluding any auto-inject recipes) contains at least one `docker-compose` recipe. A native-only selection injects nothing. Injection order in the install script is: Traefik → auto-inject recipes (sorted by id) → customer apps.
- **Not selectable.** `POST /api/v1/compose` rejects any selection that names an auto-inject recipe directly, with `error: recipe_not_selectable`.

**Security note (RW Docker socket):** Mounting `/var/run/docker.sock` read-write (as `wud` does) grants root-equivalent host access to the container. This is the accepted architectural trade-off for apply-capable update tooling; such recipes must rely on defence-in-depth (TLS, strong auth, no raw-port exposure).

Current auto-inject recipes:

| Recipe | Role |
|---|---|
| `wud` | Docker image update notifier and one-click updater |

### 4.6 Logo specification

Every customer-visible (`enabled: true`) recipe must have a logo. The logo binary lives in the recipe directory (`recipes/<id>/logo.<ext>`) and is mirrored to an IONOS Object Storage bucket by the `sync-logos` job in `recipe-pipeline.yaml` on merge.

**File requirements:**
- Extension: `.svg` only — no PNG or WEBP. SVG scales without quality loss across panel rendering densities and is the only format accepted by `af-validate` and the `sync-logos` job.
- Square or near-square aspect ratio recommended for thumbnail rendering
- File lives at `recipes/<id>/logo.svg` — git is the source of truth, S3 is a derived artifact

**Bucket layout:**

| Environment | Bucket | URL pattern |
|---|---|---|
| Production | `appfactory` | `https://appfactory.s3.eu-central-3.ionoscloud.com/recipes/<id>/<recipe_version>/logo.svg` |
| PR preview | `appfactory-dev` | `https://appfactory-dev.s3.eu-central-3.ionoscloud.com/recipes/<id>/<recipe_version>/logo.svg` |

Paths are versioned by `recipe_version`. Combined with `Cache-Control: public, max-age=31536000, immutable` on the uploaded object, this means **any logo change requires a `recipe_version` bump** — otherwise consumers see the previously-cached file forever. The `sync-logos` job refuses to merge a logo change without an accompanying `recipe_version` change.

**Integrity:** `logo_sha256` is the SHA-256 of the file content. `af-validate` recomputes the hash from the on-disk file and refuses the recipe if it diverges from the declared value. This protects against silent edits, partial uploads, and S3 drift.

**Licensing:** Recipes must declare `logo_license`. Permissible values include any SPDX identifier (`MIT`, `Apache-2.0`, `CC-BY-SA-4.0`, etc.) or the sentinel `trademark-nominative-fair-use` for cases where the logo is a third-party trademark displayed under nominative fair use (i.e. to identify the upstream product in the catalogue). For attribution-required licenses (`CC-BY*`), the upstream source URL should be set in `logo_source`.

**Disabled recipes:** `enabled: false` recipes are exempt from the `logo-required-when-enabled` rule, but if they *declare* `logo_url`, all integrity/canonicalisation rules still apply.

## 5. OS Baselines and Resource Calculation

Recipe `app_min_*` fields declare **app-only** resource requirements for RAM and disk. CPU cores are **not** declared per recipe — they are defined only in the OS baseline, since CPU scheduling is handled by the OS and doesn't sum linearly across apps.

OS and Docker runtime overhead is **not** stored in this repository. The AF API owns the OS baseline — a single `os_baseline` valid for both the VPS and bare-metal base images — and returns it as a computed field in its `/catalogue` response. It calculates total server requirements by adding the OS baseline once:

```
total_min_ram_mb  = os_baseline.os_min_ram_mb  + sum(app.app_min_ram_mb  for each selected app)
total_min_cpu_cores = os_baseline.os_min_cpu_cores  (OS baseline only, not per-app)
total_min_disk_mb = os_baseline.os_min_disk_mb + sum(app.app_min_disk_mb for each selected app)
```

Example: n8n (2048 MB) + Portainer (512 MB) with a 512 MB OS baseline = **3072 MB** total minimum RAM, **1 CPU core** minimum (from baseline).

## 6. docker-compose.yaml Conventions

- **Compose v3 format** (no `version:` key — Compose v2 CLI handles this).
- **Pinned image versions** — never use `:latest`.
- **Healthchecks** — every service must declare a Docker healthcheck.
- **Host bind mounts** — for all persistent data. Use paths like `/opt/<app-name>/<service-name>/` on the host.
- **Dedicated bridge network** — one per recipe, named `<app>-network`.
- **Environment variables** — reference `.env` file, not hardcoded values.
- **No privileged containers** unless absolutely required (document in `notes`).
- **No public database ports** — databases are internal only.

## 7. .env.template Syntax

The renderer copies `.env.template` to the VM's `.env` byte for byte — there is **no**
render-time placeholder substitution (IF-944). `{{PARAM_NAME}}`-style tokens are therefore
forbidden outright (`no-env-placeholder`, see rfc/002-recipe-rules.md) rather than resolved.
Every key is written as one of:

```
TZ=Europe/Berlin                 # static literal — the value never varies
POSTGRES_PASSWORD=               # per-VM secret — generated by this recipe's own install.sh
OPENAI_API_KEY=                  # customer-only value — the customer fills it in after install
# AF_APP_DOMAIN is not declared here — the platform writes it into .env at render time
```

An app's own FQDN is never written as a key here: it arrives as the platform's reserved
`AF_APP_DOMAIN` (IF-1417), added by the AF API renderer, not by the recipe. See
`compose-var-defined-in-env` in rfc/002-recipe-rules.md for the full reserved-key allow-list.

### 7.1 Dollar signs in resolved values

If a resolved value contains a literal `$` (for example an APR1/htpasswd hash like `$apr1$salt$digest`), the `$` must be **doubled to `$$` in the written `.env`**. Docker Compose interprets `$VAR` and `${VAR}` in `.env` values as variable references, even when the file is consumed via `env_file:`. Without escaping, compose silently expands unknown `$`-prefixed tokens to empty strings, corrupting the value.

The AF API must escape `$` → `$$` when resolving any parameter whose type permits the character (e.g. `password` parameters fed to downstream hashers). Recipe authors generating `.env` content directly in `install.sh` must do the same.

## 8. health-check.sh

- **Purpose:** CI testing only. Not deployed to the VM.
- **Interface:** Receives `$IMAGE` (for docker-compose recipes, the app's primary service URL) as argument.
- **Exit code:** 0 = healthy, non-zero = failure.
- **Timeout:** Scripts should complete within 60 seconds.

```bash
#!/usr/bin/env bash
# health-check.sh — CI-only health check
set -euo pipefail
URL="${1:?Usage: health-check.sh <url>}"
curl -fsS --max-time 10 "$URL" > /dev/null
```

## 9. install.sh

Standard interface between the Application Factory installation orchestrator and the recipe's installation process. Its responsibilities differ by `recipe_type`:

- **`docker-compose` recipes: prep-only.** `install.sh` runs *before* the containers come up — mkdir/chown of data directories, secret/config generation, anything `docker-compose.yaml` assumes already exists. It must **not** run `docker compose up` itself: the af-core-rendered top-level install archive runs each app's `install.sh` and then brings the stack up via the shared `compose-up.sh` helper (with its own retry/backoff). Checking that Docker/Compose are available is *not* the recipe's job either — that check lives once in the OS-image bootstrap, not per-recipe.
- **`native` recipes: full install.** No shared "up" helper exists for native apps, so `install.sh` performs the complete installation — package install, download/build, service startup, health verification — end to end.

Common interface, both types:

- **Interface:** Receives environment variables and resolves parameters from `.env` file.
- **Exit code:** 0 = success, non-zero = failure.
- **Timeout:** Scripts should complete within a reasonable time (implementation-specific).
- **Working directory:** Executes in the recipe directory (where this script resides).
- **Environment:** All `.env` variables are available in the script's environment.

### Example: docker-compose recipe (prep-only)

```bash
#!/usr/bin/env bash
# install.sh — Prepare n8n for docker-compose (compose-up.sh brings it up afterwards)
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Create named volumes / data directories the compose file expects
docker volume create n8n-data || true
```

### Example: bare-metal recipe

```bash
#!/usr/bin/env bash
# install.sh — Install Claude Code on bare-metal
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Install dependencies
apt-get update
apt-get install -y curl git

# Download and install Claude Code
curl -fsSL https://api.github.com/repos/anthropics/claude-code/releases/latest \
  | grep browser_download_url | grep linux-x64 \
  | cut -d '"' -f 4 | xargs -I {} curl -L {} -o /tmp/claude-code.tar.gz

tar -xzf /tmp/claude-code.tar.gz -C /opt/
ln -sf /opt/claude-code/bin/claude-code /usr/local/bin/claude-code

# Verify installation
claude-code --version || { echo "Installation failed"; exit 1; }

echo "Claude Code installed successfully"
exit 0
```

## 10. catalogue.json

Generated by `bin/build-catalogue` from all `metadata.yaml` files. Served by the AF API at startup.

```json
{
  "recipe_count": 6,
  "recipes": [
    {
      "name": "n8n",
      "display_name": "n8n",
      "description": "Low-code workflow automation tool",
      "category": "automation",
      "app_version": "1.94.1",
      "recipe_type": "docker-compose",
      "app_min_ram_mb": 2048,
      "app_min_disk_mb": 20480,
      "ports": [{"port": 5678, "protocol": "tcp", "public": true, "description": "Web UI"}],
      "parameters": ["APP_DOMAIN", "N8N_ADMIN_EMAIL"]
    }
  ]
}
```

## 11. WUD Per-container Label Matrix

Every `docker-compose` recipe should carry WUD labels on each of its services so What's Up Docker (the composition app) knows how to handle each container. The required labels depend on the container's role:

| Container role | `wud.watch` | `wud.trigger.include` | `wud.compose.file` |
|---|---|---|---|
| **App** (notify + allow one-click update) | *(omit — default true)* | `ntfy.notify,dockercompose.apply` | `/opt/<slug>/docker-compose.yml` |
| **App** (notify only, no apply) | *(omit — default true)* | `ntfy.notify` | *(omit)* |
| **Database** | `false` | *(omit)* | *(omit)* |
| **Infrastructure** (Traefik, WUD itself, proxies) | `false` | *(omit)* | *(omit)* |

**Rationale for each column:**

- `wud.watch=false` — hides the container from WUD entirely. Databases must not be auto-updated (schema migrations are not automatic); infrastructure containers must not be disrupted.
- `wud.trigger.include` — comma-separated list of `<kind>.<name>` trigger IDs. `ntfy.notify` fires automatically on every detected update; `dockercompose.apply` fires only when the user clicks **RUN** in the WUD UI.
- `wud.compose.file` — full path to the compose file inside the WUD container (after af-core's bind-mount injection). Required for the `dockercompose.apply` trigger.

**Example — recipe with one app service and one database:**

```yaml
services:
  myapp:
    image: vendor/myapp:1.2.3
    labels:
      - "wud.trigger.include=ntfy.notify,dockercompose.apply"
      - "wud.compose.file=/opt/myapp/docker-compose.yml"
    ...

  mydb:
    image: postgres:16-alpine
    labels:
      - "wud.watch=false"
    ...
```

The WUD trigger IDs (`ntfy.notify`, `dockercompose.apply`) are configured in `/opt/wud/.env` by the WUD recipe. Recipes only reference the IDs via labels — they do not configure the triggers themselves.

## 12. Git Conventions

- **Monorepo:** All recipes live in `af-recipes`.
- **Branching:** `feature/<ticket>-<topic>`, `fix/<ticket>-<topic>`.
- **Tagging:** `<app>/v<app_version>-r<recipe_version>` (e.g., `n8n/v1.94.1-r1.0.0`).
- **Review:** All changes require PR review before merge to `main`.
