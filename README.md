# af-recipes

Application Factory recipes — declarative application definitions consumed by the AF API.

## Recipe Format

Each recipe lives in `recipes/<app-name>/` and contains:

| File | docker-compose | native | Description |
|---|---|---|---|
| `metadata.yaml` | required | required | App info, parameters, resource requirements |
| `docker-compose.yaml` | required | — | Compose v3 service definition |
| `.env.template` | required | — | `{{PARAM}}` placeholders resolved at install time |
| `install.sh` | required | required | Prep only for docker-compose (compose-up.sh starts the stack); full install for native — see [rfc/001-recipe-schema.md §9](rfc/001-recipe-schema.md#9-installsh) |
| `health-check.sh` | required | required | CI-only health check script |
| `logo.svg` | required* | required* | App logo shown in catalogue thumbnails (*required when `enabled: true`) |

See [rfc/001-recipe-schema.md](rfc/001-recipe-schema.md) for the full specification.

### Logos

Every customer-visible (`enabled: true`) recipe ships an SVG logo at
`recipes/<id>/logo.svg`, referenced from `metadata.yaml` via `logo_url`,
`logo_sha256`, `logo_license`, and `logo_source`. Git is the source of truth; the
[`recipe-pipeline.yaml`](.github/workflows/recipe-pipeline.yaml) workflow mirrors
changed logos to IONOS Object Storage (the `appfactory-dev` bucket on PRs, the
`appfactory` production bucket on merge) and serves them over HTTPS on a
`recipe_version`-versioned, immutably-cached path. See
[CONTRIBUTING.md](CONTRIBUTING.md#adding-a-logo) for the how-to and
[docs/buckets.md](docs/buckets.md) for the storage/operations reference.

## Quick Reference

| App | Category | Web UI | Other Ports | Min RAM | Notes |
|-----|----------|--------|-------------|---------|-------|
| [AdGuard Home](recipes/adguard-home/) | security | `:3000` (setup), `:80` | `:53` DNS tcp+udp | 256 MB | ⚠️ incompatible with Pi-hole |
| [Apache Guacamole](recipes/guacamole/) | infrastructure | `:8080` | — | 1 GB | ⚠️ port conflict with Pi-hole |
| [Claude Code](recipes/claude-code/) | developer-tools, ai | — (native) | — | 2 GB | |
| [Gemini CLI](recipes/gemini-cli/) | developer-tools, ai | — (native) | — | 1 GB | |
| [Gitea](recipes/gitea/) | developer-tools | `:3000` | `:2222` SSH | 512 MB | ⚠️ port conflict with WUD, AdGuard |
| [Home Assistant](recipes/home-assistant/) | automation | `:8123` | — | 1 GB | bridge mode; no BT/USB |
| [Immich](recipes/immich/) | media | `:2283` | — | 4 GB | |
| [n8n](recipes/n8n/) | automation | `:5678` | — | 2 GB | |
| [Ollama](recipes/ollama/) | ai | `:11434` | — | 8 GB | GPU recommended |
| [OpenClaw](recipes/openclaw/) | ai, automation | `:18789` | — | 2 GB | |
| [OpenGist](recipes/opengist/) | developer-tools | `:6157` | `:2222` SSH | 256 MB | ⚠️ SSH port conflict with Gitea |
| [Paperless-ngx](recipes/paperless-ngx/) | productivity | `:8000` | — | 2 GB | |
| [Pi-hole](recipes/pihole/) | security | `:8080` | `:53` DNS tcp+udp | 256 MB | ⚠️ incompatible with AdGuard Home |
| [Portainer](recipes/portainer/) | infrastructure | `:9443` HTTPS | `:8000` Edge | 512 MB | |
| [Syncthing](recipes/syncthing/) | productivity | `:8384` | `:22000` tcp+udp | 256 MB | |
| [Uptime Kuma](recipes/uptime-kuma/) | monitoring | `:3001` | — | 256 MB | |
| [Vaultwarden](recipes/vaultwarden/) | security | `:80` | — | 256 MB | ⚠️ port conflict with AdGuard (post-setup) |
| [What's Up Docker](recipes/wud/) | monitoring | `:3000` | — | 256 MB | ⚠️ port conflict with Gitea, AdGuard |
| [AnyType Server](recipes/anytype-server/) | productivity | `:4830` coordinator | `:4730`, `:4630`, `:9000` | 2 GB | 5-service stack (+ MongoDB, MinIO) |
| [Paperless-AI](recipes/paperless-ai/) | productivity, ai | `:3000` | — | 512 MB | companion for Paperless-ngx; needs API token |
| [Runtipi](recipes/runtipi/) | infrastructure | `:80`, `:443` | — | 1 GB | manages own Docker apps; socket mount |
| [WireGuard Easy](recipes/wg-easy/) | security | `:51821` | `:51820/udp` VPN | 256 MB | requires NET_ADMIN cap |

> **Port conflicts** arise only when multiple apps are co-installed on the same server.
> Use `incompatible_with_apps` in `metadata.yaml` to prevent conflicting pairs from being selected together.

## Available Recipes

<table>
<tr>
<td align="center" width="33%">
<a href="recipes/n8n/">
<img src="https://img.shields.io/badge/n8n-EA4B71?style=for-the-badge&logo=n8n&logoColor=white" alt="n8n" />
</a>
<br />
<sub><b>Workflow Automation</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/2GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Connect apps and APIs with a low-code visual editor</sub>
</td>
<td align="center" width="33%">
<a href="recipes/portainer/">
<img src="https://img.shields.io/badge/Portainer-13BEF9?style=for-the-badge&logo=portainer&logoColor=white" alt="Portainer" />
</a>
<br />
<sub><b>Container Management</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/512MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>GUI for managing Docker environments</sub>
</td>
<td align="center" width="33%">
<a href="recipes/ollama/">
<img src="https://img.shields.io/badge/Ollama-000000?style=for-the-badge&logo=ollama&logoColor=white" alt="Ollama" />
</a>
<br />
<sub><b>Local LLM Runner</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/8GB_RAM-orange?style=flat-square" />
</sub>
<br />
<sub>Run large language models locally &mdash; GPU recommended</sub>
</td>
</tr>
<tr>
<td align="center" width="33%">
<a href="recipes/openclaw/">
<img src="https://img.shields.io/badge/OpenClaw_🦞-FF6B35?style=for-the-badge" alt="OpenClaw" />
</a>
<br />
<sub><b>AI Agent Runtime</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/2GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Personal AI assistant via Telegram, Discord, Slack &amp; more</sub>
</td>
<td align="center" width="33%">
<a href="recipes/claude-code/">
<img src="https://img.shields.io/badge/Claude_Code-D4A574?style=for-the-badge&logo=anthropic&logoColor=white" alt="Claude Code" />
</a>
<br />
<sub><b>AI Coding Assistant</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/native-333?style=flat-square&logo=linux&logoColor=white" />
<img src="https://img.shields.io/badge/2GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Agentic AI tool for terminal-based coding</sub>
</td>
<td align="center" width="33%">
<a href="recipes/gemini-cli/">
<img src="https://img.shields.io/badge/Gemini_CLI-8E75B2?style=for-the-badge&logo=googlegemini&logoColor=white" alt="Gemini CLI" />
</a>
<br />
<sub><b>AI Coding Assistant</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/native-333?style=flat-square&logo=linux&logoColor=white" />
<img src="https://img.shields.io/badge/1GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Interact with Google Gemini models from the terminal</sub>
</td>
</tr>
<tr>
<td align="center" width="33%">
<a href="recipes/gitea/">
<img src="https://img.shields.io/badge/Gitea-609926?style=for-the-badge&logo=gitea&logoColor=white" alt="Gitea" />
</a>
<br />
<sub><b>Git Server</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/512MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Lightweight self-hosted Git service with web interface</sub>
</td>
<td align="center" width="33%">
<a href="recipes/opengist/">
<img src="https://img.shields.io/badge/OpenGist-333?style=for-the-badge&logo=github&logoColor=white" alt="OpenGist" />
</a>
<br />
<sub><b>Gist Service</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/256MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Self-hosted pastebin and Gist service powered by Git</sub>
</td>
<td align="center" width="33%">
<a href="recipes/immich/">
<img src="https://img.shields.io/badge/Immich-4285F4?style=for-the-badge&logo=google-photos&logoColor=white" alt="Immich" />
</a>
<br />
<sub><b>Photo Management</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/4GB_RAM-orange?style=flat-square" />
</sub>
<br />
<sub>High-performance self-hosted photo and video backup</sub>
</td>
</tr>
<tr>
<td align="center" width="33%">
<a href="recipes/paperless-ngx/">
<img src="https://img.shields.io/badge/Paperless--ngx-17A589?style=for-the-badge&logo=files&logoColor=white" alt="Paperless-ngx" />
</a>
<br />
<sub><b>Document Management</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/2GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Searchable archive for physical documents</sub>
</td>
<td align="center" width="33%">
<a href="recipes/vaultwarden/">
<img src="https://img.shields.io/badge/Vaultwarden-175DDC?style=for-the-badge&logo=bitwarden&logoColor=white" alt="Vaultwarden" />
</a>
<br />
<sub><b>Password Manager</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/256MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Lightweight Bitwarden-compatible password manager</sub>
</td>
<td align="center" width="33%">
<a href="recipes/wg-easy/">
<img src="https://img.shields.io/badge/WireGuard_Easy-88171A?style=for-the-badge&logo=wireguard&logoColor=white" alt="WireGuard Easy" />
</a>
<br />
<sub><b>VPN Server</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/256MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>WireGuard VPN with a simple web UI</sub>
</td>
</tr>
<tr>
<td align="center" width="33%">
<a href="recipes/adguard-home/">
<img src="https://img.shields.io/badge/AdGuard_Home-68BC71?style=for-the-badge&logo=adguard&logoColor=white" alt="AdGuard Home" />
</a>
<br />
<sub><b>DNS Ad-Blocker</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/256MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Network-wide DNS filtering and privacy protection</sub>
</td>
<td align="center" width="33%">
<a href="recipes/pihole/">
<img src="https://img.shields.io/badge/Pi--hole-96060C?style=for-the-badge&logo=pi-hole&logoColor=white" alt="Pi-hole" />
</a>
<br />
<sub><b>DNS Ad-Blocker</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/256MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Network-wide DNS sinkhole for ad blocking</sub>
</td>
<td align="center" width="33%">
<a href="recipes/syncthing/">
<img src="https://img.shields.io/badge/Syncthing-0891D1?style=for-the-badge&logo=syncthing&logoColor=white" alt="Syncthing" />
</a>
<br />
<sub><b>File Sync</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/256MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Continuous P2P file synchronization between devices</sub>
</td>
</tr>
<tr>
<td align="center" width="33%">
<a href="recipes/uptime-kuma/">
<img src="https://img.shields.io/badge/Uptime_Kuma-5CDD8B?style=for-the-badge&logo=uptimekuma&logoColor=black" alt="Uptime Kuma" />
</a>
<br />
<sub><b>Monitoring</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/256MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Self-hosted uptime and service monitoring</sub>
</td>
<td align="center" width="33%">
<a href="recipes/wud/">
<img src="https://img.shields.io/badge/What's_Up_Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="WUD" />
</a>
<br />
<sub><b>Update Monitor</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/256MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Get notified when new container image versions are available</sub>
</td>
<td align="center" width="33%">
<a href="recipes/guacamole/">
<img src="https://img.shields.io/badge/Guacamole-F9A825?style=for-the-badge&logo=apache&logoColor=white" alt="Apache Guacamole" />
</a>
<br />
<sub><b>Remote Desktop Gateway</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/1GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Clientless RDP, VNC and SSH via browser</sub>
</td>
</tr>
<tr>
<td align="center" width="33%">
<a href="recipes/home-assistant/">
<img src="https://img.shields.io/badge/Home_Assistant-41BDF5?style=for-the-badge&logo=home-assistant&logoColor=white" alt="Home Assistant" />
</a>
<br />
<sub><b>Home Automation</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/1GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Open source home automation with local control</sub>
</td>
<td align="center" width="33%">
<a href="recipes/paperless-ai/">
<img src="https://img.shields.io/badge/Paperless--AI-17A589?style=for-the-badge&logo=openai&logoColor=white" alt="Paperless-AI" />
</a>
<br />
<sub><b>AI Document Analysis</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/512MB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>AI-powered auto-tagging companion for Paperless-ngx</sub>
</td>
<td align="center" width="33%">
<a href="recipes/runtipi/">
<img src="https://img.shields.io/badge/Runtipi-FF6B35?style=for-the-badge&logo=docker&logoColor=white" alt="Runtipi" />
</a>
<br />
<sub><b>App Store</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/1GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Self-hosted app store for easy application deployment</sub>
</td>
</tr>
<tr>
<td align="center" width="33%">
<a href="recipes/anytype-server/">
<img src="https://img.shields.io/badge/AnyType_Server-1A73E8?style=for-the-badge&logo=notion&logoColor=white" alt="AnyType Server" />
</a>
<br />
<sub><b>Knowledge Management</b></sub>
<br />
<sub>
<img src="https://img.shields.io/badge/docker--compose-2496ED?style=flat-square&logo=docker&logoColor=white" />
<img src="https://img.shields.io/badge/2GB_RAM-grey?style=flat-square" />
</sub>
<br />
<sub>Self-hosted sync server for AnyType notes &amp; knowledge base</sub>
</td>
<td align="center" width="33%">
</td>
<td align="center" width="33%">
</td>
</tr>
</table>

## Build Catalogue

Generate `catalogue.json` from all `metadata.yaml` files:

```bash
python3 bin/build-catalogue
```

Requires `pyyaml` (`pip install pyyaml`).

## Contributing

1. Create a new directory under `recipes/` matching your app's `name` field.
2. Add all required files for your recipe type.
3. Run `python3 bin/build-catalogue` to validate.
4. Submit a PR for review.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide, including how to add a
recipe logo and the logo licensing rules.

## Testing

The CI workflows, and — most importantly — **how to test a branch or a specific
version**. For the OS image these recipes install onto, see
[`if-main-ubuntu-2604-af`](https://github.com/IONOS-Server-Technology/if-main-ubuntu-2604-af#ci-pipeline-build_releaseyaml).

### The workflows

| Workflow | Trigger | Where it runs | Cost / time |
|----------|---------|---------------|-------------|
| [`recipe-pipeline.yaml`](.github/workflows/recipe-pipeline.yaml) | PR / push to `main` on `recipes/**` or `bin/build-catalogue` | GitHub runner (static + S3 logo sync) | seconds–1 min |
| [`test-recipes-docker.yaml`](.github/workflows/test-recipes-docker.yaml) | PR to `main` on `recipes/**`, manual | `docker compose` on the runner | ~2–5 min |
| [`test-recipes-live.yaml`](.github/workflows/test-recipes-live.yaml) | PR to `main` on `recipes/**`, push on `feature/IF-547-**`, manual | IONOS CoreVPS VM + per-branch `af-api` in k8s | ~10–15 min, IONOS quota |
| [`nightly-regression.yaml`](.github/workflows/nightly-regression.yaml) | Daily `0 2 * * *` UTC, manual | Reuses `test-recipes-live` via `workflow_call` (all enabled recipes) | ~30–60 min |
| [`debug-af-api.yaml`](.github/workflows/debug-af-api.yaml) | Manual | Deploys `af-api` and holds it for `kubectl` | as long as you hold it |
| [`af-api-cleanup.yaml`](.github/workflows/af-api-cleanup.yaml) | Manual | Reaps orphaned ephemeral `af-api` deployments | seconds |

- **`recipe-pipeline.yaml`** — the static gate plus (mutating) logo mirroring:
  `sync-logos` uploads changed `recipes/<id>/logo.svg` to IONOS Object Storage
  (`appfactory-dev` on a PR, **prod + dev** on merge to `main`; **fails a logo
  change that doesn't bump `recipe_version`**); `validate` runs `bin/build-catalogue`
  and checks required files / compose structure / `.env.template` placeholders;
  `af-validate-rfc002` runs the [RFC-002](rfc/002-recipe-rules.md) rules and HEADs
  every `logo_url`. (This replaced the old `validate-recipes.yaml`.)
- **`test-recipes-docker.yaml`** (Phase 1) — spins up the recipe's
  `docker-compose.yaml` on the runner, runs `health-check.sh` against `localhost`,
  tears it down. Matrix = changed compose recipes (native recipes dropped here).
- **`test-recipes-live.yaml`** (Phase 2) — the production path: builds a per-branch
  `af-api`, deploys it to a per-run k8s NodePort, renders cloud-init via `/compose`,
  provisions a **real CoreVPS VM**, and runs the recipe's health check on it. Matrix
  = changed recipes with `enabled: true`. Pipeline shape:

  ```
  detect-changed-recipes  →  trigger-af-api-build  →  deploy-af-api
        →  test-recipes (matrix)                    →  cleanup-af-api (always)
             ├─ discover "_af" image UUID (or use the image_uuid input)
             ├─ /compose → cloud-init → patch dev-mode/http
             ├─ probe /bootstrap with the JWT
             └─ ImageTester: provision VM, inject cloud-init, run
                tests/recipe-health-check.conf (SSH probes + health-check.sh on the VM)
  ```
- **`nightly-regression.yaml`** — a dedicated scheduled workflow that reuses
  `test-recipes-live.yaml` via `workflow_call` (`with: all_enabled: true`), so the
  nightly runs the **same** production path over every enabled recipe — same run, no
  second runner, no separate renderer. Scheduled runs fire only from the default
  branch; use `workflow_dispatch` to run it by hand.
- **`debug-af-api.yaml`** — deploys an `af-api` for a chosen `af_recipes_ref` and
  holds it `hold_minutes` (default 30) so you can attach with your own `kubectl`
  (`exec`, `logs`). `skip_build=true` reuses the image already in Harbor.
- **`af-api-cleanup.yaml`** — reaps ephemeral `af-api` deployments a force-cancelled
  run left behind (`max_age_hours`, default 6.5).

### How to test a branch or a specific version

1. **Recipe change (single-repo):** open a PR touching `recipes/**`. That runs, in
   parallel, `recipe-pipeline.yaml` (validation), `test-recipes-docker.yaml` (fast),
   and `test-recipes-live.yaml` (full VM install of every *enabled* changed recipe).
   No cross-repo setup — `af-api`/`af-core` lookups fall back to `main`.
2. **Recipe change that needs `af-api`/`af-core` too:** give the other repos a branch
   with the **same name** (see [Same-name branch resolution](#same-name-branch-resolution)).
   The live test builds `af-api` from your branch and runs it.
3. **One recipe on demand (no PR):** dispatch `test-recipes-docker.yaml` (fast) or
   `test-recipes-live.yaml` (full VM) with `recipes=<name>` (comma-separated for
   several; empty ⇒ pilot set `n8n,portainer,ollama` for the docker workflow).
4. **Against a specific OS image version:** dispatch `test-recipes-live.yaml` with
   `image_uuid=<uuid>` (optionally plus `recipes=<name>`) to skip image discovery:

   ```bash
   ionosctl image list -o json \
     | jq -r '.items[] | select(.properties.name | test("_af.qcow2";"i"))
              | "\(.properties.createdDate) \(.id) \(.properties.name)"' \
     | sort | tail
   ```
5. **Debug a broken `af-api`:** dispatch `debug-af-api.yaml`, then attach with
   `kubectl` using the deployment name it prints.

### OS-image integration

The OS image repo
[`if-main-ubuntu-2604-af`](https://github.com/IONOS-Server-Technology/if-main-ubuntu-2604-af)
calls **into** this repo: after building the image it publishes it to IONOS Cloud
and dispatches `test-recipes-live.yaml` here with that image's `image_uuid` (and the
resolved `af-recipes` ref), so *all enabled recipes* are installed on the brand-new
image, then deletes the throwaway image. A green OS-image build therefore proves the
image can bootstrap the whole catalogue.

### Same-name branch resolution

For each of `af-api` and `af-core`, the live workflow does:

```
branch = current af-recipes branch (head.ref on a PR, ref_name otherwise)
if branch exists on the target repo → use it   else → fall back to main
```

`af-api` is built from its resolved ref (image tagged with the sanitised branch
name); `af-core` is passed as `af_core_ref` into that build. `recipe-pipeline.yaml`
and `test-recipes-docker.yaml` do the same lookup for `af-core`.

**Practical rule:** when a change spans repos, use the **same branch name**
everywhere (`af-recipes`, `af-api`, `af-core`, and the OS image). Single-repo PRs
need no setup — missing branches fall back to `main`.

### `test-params.yaml` — recipe-local test inputs

A recipe may ship `recipes/<slug>/test-params.yaml` to supply parameter values that
`metadata.yaml` declares. Read by `scripts/call-compose.py` / `probe-bootstrap.py` and merged with
auto-generated (`auto_generate: true`) and `default:` values. Format is a flat
`KEY: value` mapping keyed by parameter `name`. **Required** only when `metadata.yaml`
has parameters that are neither `auto_generate: true` nor have a `default:` — else the
renderer aborts with `Missing required parameters: …`. Use obviously fake values
(`example.com`, `test_*`); they land on a throwaway VM.

```yaml
# recipes/n8n/test-params.yaml
APP_DOMAIN: n8n.example.com
N8N_ADMIN_EMAIL: admin@example.com
POSTGRES_PASSWORD: "test_postgres_password_123"
N8N_ENCRYPTION_KEY: "test_encryption_key_1234567890"
```

### Native recipes

Recipes without `docker-compose.yaml` (`recipe_type: native`, e.g. `claude-code`,
`gemini-cli`) install directly via `install.sh`. They are **excluded** from the
docker workflow by design, and included in the live/nightly workflows **only when
`enabled: true`**. The two native recipes are currently `enabled: false`, so they are
covered by `recipe-pipeline.yaml` (static) only — no end-to-end VM run yet.

### Pointers

- [docs/health-check-spec.md](docs/health-check-spec.md) — the `health-check.sh` contract.
- [docs/buckets.md](docs/buckets.md) — logo storage / Object Storage operations.
- [tests/recipe-health-check.conf](tests/recipe-health-check.conf) — the
  `python-dwh-testsuite` config the live/nightly workflows drive.
- `scripts/call-compose.py`, `scripts/probe-bootstrap.py`,
  `scripts/patch-cloudinit-dev-mode.py` — helpers for talking to the per-branch `af-api`.
