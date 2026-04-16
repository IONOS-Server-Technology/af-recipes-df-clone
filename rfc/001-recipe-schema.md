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
| `bare-metal` | Application installed directly on the OS (no Docker) | `metadata.yaml`, `install.sh`, `health-check.sh` |

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
│   ├── claude-code/              # bare-metal example
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
| `name` | string | yes | Machine-readable slug (lowercase, hyphens). Must match directory name. |
| `display_name` | string | yes | Human-readable name for UI display. |
| `description` | string | yes | One-line description of the application. |
| `categories` | list[enum] | yes | Application categories, one or more (see §4.2). |
| `app_version` | string | yes | Upstream application version being deployed. |
| `recipe_version` | string | yes | Recipe format version (semver). |
| `recipe_type` | enum | yes | `docker-compose` or `bare-metal`. |
| `upstream_url` | string | yes | URL to the upstream project (GitHub, website). |
| `app_min_ram_mb` | integer | yes | Minimum RAM in MB required by the application (excluding OS/Docker overhead). |
| `app_min_disk_mb` | integer | yes | Minimum disk space in MB required by the application. |
| `supported_os` | list[string] | yes | Supported OS list (e.g., `["ubuntu-26.04"]`). |
| `ports` | list[port] | no | Network ports (see §4.3). |
| `parameters` | list[parameter] | yes | Customer-facing parameters (see §4.4). |
| `incompatible_with` | list[string] | no | App IDs that cannot be co-installed (e.g., GPU conflicts, port clashes). Cloud Panel uses this to prevent invalid combinations during app selection. |
| `notes` | string | no | Free-text notes (caveats, limitations). |

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

## 11. Git Conventions

- **Monorepo:** All recipes live in `af-recipes`.
- **Branching:** `feature/<ticket>-<topic>`, `fix/<ticket>-<topic>`.
- **Tagging:** `<app>/v<app_version>-r<recipe_version>` (e.g., `n8n/v1.94.1-r1.0.0`).
- **Review:** All changes require PR review before merge to `main`.
