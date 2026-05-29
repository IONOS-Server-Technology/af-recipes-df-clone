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
├── os-baselines.yaml             # OS/Docker overhead per supported OS
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
| `supported_os` | list[string] | yes | Supported OS list (e.g., `["ubuntu-26.04"]`). |
| `ports` | list[port] | no | Network ports (see §4.3). |
| `parameters` | list[parameter] | yes | Customer-facing parameters (see §4.4). |
| `incompatible_with_apps` | list[string] | no | App IDs that cannot be co-installed (e.g., GPU conflicts, port clashes). Cloud Panel uses this to prevent invalid combinations during app selection. |
| `notes` | string | no | Free-text notes (caveats, limitations). |
| `composition` | boolean | no | If `true`, marks this recipe as a **composition app** — auto-injected by af-core when the customer selects at least one `recipe_type: docker-compose` recipe. Composition apps are hidden from the customer-facing catalogue (`enabled: false`) and are not customer-selectable. See §4.5. |
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
| `description` | string | yes | What this port is for (e.g., "Web UI"). |

### 4.4 Parameter Object

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Machine-readable parameter name (UPPER_SNAKE_CASE). |
| `display_name` | string | yes | Human-readable label for UI. |
| `type` | enum | yes | `string`, `email`, `domain`, `password`, `boolean`, `integer`. |
| `required` | boolean | yes | Whether the customer must provide this value. |
| `default` | any | no | Default value if not provided. |
| `auto_generate` | boolean | no | If true, AF API generates a cryptographically secure value. Used for passwords/secrets. |
| `description` | string | no | Help text for the customer. |
| `validation` | string | no | Regex pattern for validation. |

### 4.5 Composition Apps

A **composition app** is a recipe that af-core automatically injects alongside any customer-selected `docker-compose` recipe. It is infrastructure the AF platform manages transparently — not a user-selectable application.

Rules:
- `composition: true` implies `enabled: false`. The recipe never appears in the customer-facing catalogue.
- af-core unconditionally injects composition apps when at least one `docker-compose` recipe is selected.
- af-core may inject additional volumes, networks, or labels into a composition app's `docker-compose.yaml` at render time (e.g. `/opt/<app>:/opt/<app>` bind-mounts for applyable stacks).

**Security note for composition apps with RW Docker socket access:** Mounting `/var/run/docker.sock` read-write (as `wud` does) grants root-equivalent host access to the container. This is the accepted architectural trade-off for apply-capable update tooling. Recipe authors must document this in the `notes` field and ensure defence-in-depth (TLS, strong auth, no raw-port exposure).

Current composition apps:

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

OS and Docker runtime overhead is defined separately in `os-baselines.yaml`:

```yaml
baselines:
  ubuntu-26.04:
    os_min_ram_mb: 512
    os_min_cpu_cores: 1
    os_min_disk_mb: 5120
```

The AF API calculates total server requirements by adding the OS baseline once:

```
total_min_ram_mb  = os_baseline.os_min_ram_mb  + sum(app.app_min_ram_mb  for each selected app)
total_min_cpu_cores = os_baseline.os_min_cpu_cores  (OS baseline only, not per-app)
total_min_disk_mb = os_baseline.os_min_disk_mb + sum(app.app_min_disk_mb for each selected app)
```

Example: n8n (2048 MB) + Portainer (512 MB) on Ubuntu 26.04 (512 MB baseline) = **3072 MB** total minimum RAM, **1 CPU core** minimum (from baseline).

Every `supported_os` entry in a recipe must have a corresponding entry in `os-baselines.yaml`. The `build-catalogue` script validates this at build time and embeds the baselines into `catalogue.json`.

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

Parameters use `{{PARAM_NAME}}` double-curly-brace placeholders:

```
APP_DOMAIN={{APP_DOMAIN}}
ADMIN_EMAIL={{ADMIN_EMAIL}}
DB_PASSWORD={{DB_PASSWORD}}
```

The consuming system (AF API / install script) resolves placeholders with customer-provided or auto-generated values and writes the final `.env` file.

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

Standard interface between the Application Factory installation orchestrator and the recipe's installation process.

- **Purpose:** Orchestrate the installation of the application on the target system.
- **Interface:** Receives environment variables and resolves parameters from `.env` file.
- **Exit code:** 0 = success, non-zero = failure.
- **Timeout:** Scripts should complete within a reasonable time (implementation-specific).
- **Working directory:** Executes in the recipe directory (where this script resides).
- **Environment:** All `.env` variables are available in the script's environment.
- **Responsibilities:**
  - Load and validate the `.env` file (with parameters already resolved).
  - Deploy the application (docker compose up for docker-compose recipes, package installation for bare-metal).
  - Ensure the application starts successfully.
  - Configure application-specific settings (if needed).

### Example: docker-compose recipe

```bash
#!/usr/bin/env bash
# install.sh — Install n8n via docker-compose
set -euo pipefail

# Load resolved parameters from .env
set -a
source .env
set +a

# Ensure Docker and Docker Compose are available
command -v docker >/dev/null || { echo "Error: Docker not installed"; exit 1; }
command -v docker-compose >/dev/null || { echo "Error: Docker Compose not installed"; exit 1; }

# Create named volumes
docker volume create n8n-data || true

# Deploy application
docker-compose up -d

# Wait for service to be healthy (max 60 seconds)
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if docker-compose exec -T n8n curl -fsS http://localhost:5678 > /dev/null 2>&1; then
    echo "n8n is healthy"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 1
done

echo "Error: n8n failed to become healthy"
exit 1
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
  "os_baselines": {
    "ubuntu-26.04": {
      "os_min_ram_mb": 512,
      "os_min_cpu_cores": 1,
      "os_min_disk_mb": 5120
    }
  },
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
