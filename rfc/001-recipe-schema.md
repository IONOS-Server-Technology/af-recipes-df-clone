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
| `docker-compose` | Containerized application deployed via Docker Compose | `metadata.yaml`, `docker-compose.yaml`, `.env.template`, `health-check.sh` |
| `bare-metal` | Application installed directly on the OS (no Docker) | `metadata.yaml`, `health-check.sh` |

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
│   │   └── health-check.sh
│   ├── claude-code/              # bare-metal example
│   │   ├── metadata.yaml
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
| `category` | enum | yes | Application category (see §4.2). |
| `app_version` | string | yes | Upstream application version being deployed. |
| `recipe_version` | string | yes | Recipe format version (semver). |
| `recipe_type` | enum | yes | `docker-compose` or `bare-metal`. |
| `upstream_url` | string | yes | URL to the upstream project (GitHub, website). |
| `app_min_ram_mb` | integer | yes | Minimum RAM in MB required by the application (excluding OS/Docker overhead). |
| `app_min_cpu_cores` | integer | yes | Minimum CPU cores required by the application. |
| `app_min_disk_gb` | integer | yes | Minimum disk space in GB required by the application. |
| `supported_os` | list[string] | yes | Supported OS list (e.g., `["ubuntu-26.04"]`). |
| `ports` | list[port] | no | Network ports (see §4.3). |
| `parameters` | list[parameter] | yes | Customer-facing parameters (see §4.4). |
| `dependencies` | list[dependency] | no | Other services bundled in the recipe (see §4.5). |
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

### 4.5 Dependency Object

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Dependency name (e.g., "PostgreSQL"). |
| `version` | string | yes | Pinned version. |
| `bundled` | boolean | yes | Always `true` — each recipe bundles its own dependencies. |

## 5. OS Baselines and Resource Calculation

Recipe `app_min_*` fields declare **app-only** resource requirements. OS and Docker runtime overhead is defined separately in `os-baselines.yaml`:

```yaml
baselines:
  ubuntu-26.04:
    os_min_ram_mb: 512
    os_min_cpu_cores: 1
    os_min_disk_gb: 5
```

The AF API calculates total server requirements by adding the OS baseline once:

```
total_min_ram_mb  = os_baseline.os_min_ram_mb  + sum(app.app_min_ram_mb  for each selected app)
total_min_cpu_cores = os_baseline.os_min_cpu_cores + sum(app.app_min_cpu_cores for each selected app)
total_min_disk_gb = os_baseline.os_min_disk_gb + sum(app.app_min_disk_gb for each selected app)
```

Example: n8n (2048 MB) + Portainer (512 MB) on Ubuntu 26.04 (512 MB baseline) = **3072 MB** total minimum RAM.

Every `supported_os` entry in a recipe must have a corresponding entry in `os-baselines.yaml`. The `build-catalogue` script validates this at build time and embeds the baselines into `catalogue.json`.

## 6. docker-compose.yaml Conventions

- **Compose v3 format** (no `version:` key — Compose v2 CLI handles this).
- **Pinned image versions** — never use `:latest`.
- **Healthchecks** — every service must declare a Docker healthcheck.
- **Named volumes** — for all persistent data.
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

## 9. catalogue.json

Generated by `bin/build-catalogue` from all `metadata.yaml` files. Served by the AF API at startup.

```json
{
  "os_baselines": {
    "ubuntu-26.04": {
      "os_min_ram_mb": 512,
      "os_min_cpu_cores": 1,
      "os_min_disk_gb": 5
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
      "app_min_cpu_cores": 2,
      "app_min_disk_gb": 20,
      "ports": [{"port": 5678, "protocol": "tcp", "public": true, "description": "Web UI"}],
      "parameters": ["APP_DOMAIN", "N8N_ADMIN_EMAIL"]
    }
  ]
}
```

## 10. Git Conventions

- **Monorepo:** All recipes live in `af-recipes`.
- **Branching:** `feature/<ticket>-<topic>`, `fix/<ticket>-<topic>`.
- **Tagging:** `<app>/v<app_version>-r<recipe_version>` (e.g., `n8n/v1.94.1-r1.0.0`).
- **Review:** All changes require PR review before merge to `main`.
