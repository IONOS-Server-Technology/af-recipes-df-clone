# Testing Pipeline

This document describes the CI workflows that validate recipes in this repository: when
each one fires, what it does, what it costs, and how the pieces fit together.

## TL;DR

| Workflow | Trigger | Where it runs | Cost / time | Owner |
|----------|---------|---------------|-------------|-------|
| `test-recipes-docker.yaml` | PR on `recipes/**` (compose recipes only) | `docker compose` on the GitHub runner | ~2–5 min | Andreas Brämert |
| `test-recipes-live.yaml` | PR on `recipes/**`, push on `feature/IF-547-**`, manual | IONOS CoreVPS VM + per-branch `af-api` deploy in k8s | ~10–15 min, costs IONOS quota | IF-547 |
| `nightly-regression.yaml` | Daily `0 2 * * *` UTC, manual | Same as live, across **all** recipes | ~30–60 min full sweep | IF-547 |
| `validate-recipes.yaml` | PR on `recipes/**` | Static — runs on the runner | seconds | af-recipes baseline |

All three live/nightly workflows share the same VM-provisioning stack
(`python-dwh-image-build-algorithm.ImageTester` + `python-dwh-testsuite`); they only
differ in how the recipe set is detected and which branches of `af-api` / `af-core`
they target.

## Workflow walkthroughs

### `test-recipes-docker.yaml` — fast "compose up" smoke test

Spins up the recipe's `docker-compose.yaml` directly on the GitHub Actions runner, runs
`health-check.sh` against it, and tears the stack back down. No VM is involved.

- **Trigger:** PR on `recipes/**`, plus `workflow_dispatch` with an optional recipe list.
- **Matrix:** every recipe under `recipes/<slug>/` **that has a `docker-compose.yaml`**.
  The filter `is_docker_compose_recipe()` (see step `Build test matrix`) drops native
  recipes (see "Native recipes" below).
- **Health check:** `bash recipes/<slug>/health-check.sh`. Because the stack and the script
  both live on the runner, `localhost` works here — unlike in the live workflow.
- **Failure logs:** `docker compose logs --tail=150` on failure, attached to the run.

### `test-recipes-live.yaml` — real VM, real `af-api`

Mirrors the production path as closely as the runner can: a per-branch `af-api`
deployment renders cloud-init via its `/compose` endpoint, the cloud-init is injected
into a real CoreVPS VM, and the recipe's health check is exercised after install.

Pipeline shape:

```
detect-changed-recipes
        │
        ▼
trigger-af-api-build  ──►  Harbor: imagefactory/af-api:<branch-tag>
        │
        ▼
deploy-af-api  (per-run k8s Deployment + NodePort Service)
        │
        ▼
test-recipes (matrix)
   ├─ Discover Ubuntu 26.04 image UUID
   ├─ Generate cloud-init via /compose against the deployed af-api
   ├─ Probe /bootstrap with the JWT
   └─ Run ImageTester
        ├─ Provision VM, inject cloud-init
        ├─ Wait for SSH
        └─ Drive tests/recipe-health-check.conf
              ├─ exec_vm  : SSH probes (install dir, docker images, bootstrap reachable)
              └─ exec_local: bash recipes/<slug>/health-check.sh   ← see health-check-spec.md
        │
        ▼
cleanup-af-api  (always)
```

- **Trigger:** PR on `recipes/**`, push on `feature/IF-547-**`, `workflow_dispatch`.
- **Matrix:** **all** changed recipes — no `docker-compose.yaml` filter, so native recipes
  are part of the matrix but currently fail the install path (see "Native recipes" below).
- **af-api source:** built on demand from the same-name branch (see below); image lands
  in Harbor under `imagefactory/af-api:<sanitised-branch>`.
- **af-api lifetime:** per-run Deployment + NodePort, deleted in `cleanup-af-api` even on
  failure.
- **JWE key:** generated fresh per deployment via `openssl genrsa` and pinned via
  `JWE_PRIVATE_KEY_PEM`. The DEV-MODE auto-generate fallback in `af-api` is incompatible
  with `--workers > 1` because each worker would generate its own ephemeral key.
- **Health check runner:** see `docs/health-check-spec.md` — `health-check.sh` runs on
  the runner, not on the VM; use `$SERVERIP`, not `localhost`.

### `nightly-regression.yaml` — scheduled full sweep

Same VM stack as the live workflow, but enumerates every recipe under `recipes/` instead
of filtering to changed ones, and runs at 02:00 UTC daily.

- **Trigger:** `schedule: 0 2 * * *`, plus `workflow_dispatch`.
- **Matrix:** all recipes; `max-parallel: 3` to stay inside the IONOS VM quota.
- **Notification:** none. Failures are visible in the GitHub Actions UI only — no Slack,
  no chat webhook. (Earlier versions of this workflow had a Slack step but the team
  doesn't use Slack, and the payload didn't list which recipes failed; the step was
  removed rather than rewritten because the GitHub Actions UI already provides the
  per-matrix-entry status.)

### `validate-recipes.yaml` — static checks

Independent baseline pipeline maintained by Oliver Knabe (af-recipes mainline). Validates
`metadata.yaml` schema, `docker compose config` syntax, `.env.template` placeholder
coverage, and the security checks. Does not boot anything. Documented here for
completeness — it is not part of IF-547.

## `test-params.yaml` — recipe-local test inputs

Each recipe that runs in the live workflow needs a way for CI to supply parameter
values that the recipe's `metadata.yaml` declares. That's `test-params.yaml`.

### Location and lookup

```
recipes/<slug>/test-params.yaml
```

Read by `scripts/render-cloudinit.py` (used as a thin wrapper on `af-core`'s renderer):
the file is loaded as YAML and the resulting dict is merged with auto-generated values
for `auto_generate: true` parameters and `default:` fallbacks from `metadata.yaml`.

### Format

Flat `key: value` mapping where each key is a parameter `name` from `metadata.yaml`.
Strings, ints, and bools are passed through verbatim into the cloud-init `.env`.

```yaml
# recipes/n8n/test-params.yaml
APP_DOMAIN: n8n.example.com
N8N_ADMIN_EMAIL: admin@example.com
POSTGRES_PASSWORD: "test_postgres_password_123"
N8N_ENCRYPTION_KEY: "test_encryption_key_1234567890"
```

### When to add one

- Required if `metadata.yaml` declares parameters that are **not** `auto_generate: true`
  and have **no** `default:` value. Without it the renderer aborts with
  `Missing required parameters: …`.
- Optional otherwise — auto-generated and default-backed parameters work without an entry.

### What to put in

These values land on a throwaway test VM that is destroyed at end of run. Use obviously
fake values (`example.com`, `test_*`, `admin@example.com`). **Do not** put real domains,
credentials, or anything you wouldn't paste into a public PR.

## Same-name branch resolution

Many recipe changes need a matching `af-api` and/or `af-core` change. The live workflow
resolves those automatically.

For each of `af-api` and `af-core`, the workflow steps `Resolve af-api branch ref` /
`Resolve af-core branch ref` do:

```
branch = current af-recipes branch (head.ref on a PR, ref_name otherwise)
if branch exists on the target repo → use it
else → fall back to main
```

The resolved refs are passed downstream:

- `af-api` is built from the resolved ref (and the resulting image is tagged with the
  sanitised af-recipes branch name).
- `af-core` is passed through as `af_core_ref` in the `build.yaml` dispatch payload, then
  read by `af-api`'s `prepare-recipes.sh` as the `AF_RECIPES_REF` / `AF_CORE_REF` env vars
  (the underscored env names are intentional — JIRA's markdown converter mangles them,
  so they appear with dashes in comments).

Practical workflow: open feature branches with the **same name** across `af-recipes`,
`af-api`, and `af-core` when changes span repositories. Branches that don't exist
silently fall back to `main`, so single-repo PRs need no extra setup.

## Native recipes

Recipes without `docker-compose.yaml` (e.g. `claude-code`, `gemini-cli`) are described
as `recipe_type: native` in `metadata.yaml`. Their `install.sh` installs the application
directly on the host (apt + binary download or similar) rather than via Docker.

Coverage in CI:

- `test-recipes-docker.yaml`: **excluded by design** — `is_docker_compose_recipe()`
  drops them from the matrix; `docker compose up` has nothing to do for them.
- `test-recipes-live.yaml`: **included** in the matrix but currently no end-to-end
  green run exists. `validate-recipes.yaml` (static) does cover them.
- `nightly-regression.yaml`: same as live.

This is intentional for now: `claude-code` and `gemini-cli` are both `enabled: false`
in `metadata.yaml`, so they aren't customer-facing yet. End-to-end native coverage is
tracked as a follow-up — do not assume a new native recipe is being tested in CI until
that follow-up lands.

## Useful pointers

- `docs/health-check-spec.md` — what `health-check.sh` must implement and where it runs.
- `tests/recipe-health-check.conf` — the `python-dwh-testsuite` config that drives the
  live and nightly workflows. Split into `exec_local` (runner) and `exec_vm` (SSH to VM)
  test buckets.
- `scripts/render-cloudinit.py` — CLI used by `nightly-regression.yaml`; the live
  workflow uses the deployed `af-api`'s `/compose` endpoint instead so the production
  code path is exercised.
- `scripts/call-compose.py`, `scripts/probe-bootstrap.py` — helpers the live workflow
  uses to talk to the per-branch `af-api`.
