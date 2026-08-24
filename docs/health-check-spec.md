# Health Check Spec — `health-check.sh`

## Purpose

`health-check.sh` is a **CI-only script** run by the live test workflow after a recipe is
installed on a test VM. It verifies that the application is actually reachable and healthy.

It is **not** deployed to production VMs and is **separate** from Docker Compose healthchecks
(which are declared in `docker-compose.yaml` and govern container restarts).

## Where the script runs — IMPORTANT

The script is uploaded to the test VM and executed **there**. In the generated
`python-dwh-testsuite` config it is a `Plugins.UploadExecute.Test` with `executors = exec_vm`:
the file is SFTP'd to `/tmp/af-hc-<recipe>.sh` over the `exec_vm` SSH session, then run on that
same session as `bash /tmp/af-hc-<recipe>.sh`. (The config is generated per-combination by
`scripts/gen-health-check-conf.py`, which is the sole definition of the suite — there is no
committed config it is derived from.)

Consequences:

- **`127.0.0.1` is the application host.** The script runs on the VM the app was installed on,
  so `curl -sf http://127.0.0.1:5678/healthz` is the correct probe. Do **not** try to address
  the VM by its public IP from inside the script.
- **No environment variables are available.** The script is executed over a bare SSH command
  channel — no PTY, no login shell, no inherited environment. `SERVERIP`, `RECIPE_NAME`,
  `WORKFLOW_HOMEDIR`, `SSH_KEY_ABSPATH` and `AF_API_URL` are **unset**. The script must be
  self-contained: hardcode the port and path, or read them from files on the VM.
- **The working directory is `/root`**, not the recipe directory. Never use a relative path —
  `source .env` will not find `/opt/<app>/.env`.
- **No arguments are passed.** Both invocation sites call the script bare (see
  [Both invocation sites](#both-invocation-sites)).
- VM-side checks that need more than the application itself (filesystem layout, `docker images`,
  `systemctl status …`) belong in the generated config as `Plugins.Ssh.Test` entries, not in
  `health-check.sh`. Define them as an INI template under `tests/checks/` and add an entry
  to `tests/checks/manifest.yaml` giving the template name, scope (`per_vm` or `per_app`),
  and gate (conventionally `always`). See the existing templates for examples
  (`test_install_dir.conf.tmpl`, `test_docker_images.conf.tmpl`, `test_bootstrap_reachable.conf.tmpl`).
  The per-app sections carry an `_<app>` suffix — `test_install_dir_immich` — while VM-wide ones
  such as `test_docker_images` and `test_bootstrap_reachable` stay single.
  If the check needs a condition that is not one of the existing gates, the gate logic must be
  added to the generator's `resolve_gates` / `resolve_app_gates` functions first — the manifest
  only *names* gates, and naming an unknown gate is a hard error (the config fails to generate).

### Per-recipe override

A recipe may ship `recipes/<id>/test-checks.yaml`. If present, it **fully replaces** (does not
merge with) that recipe's per-app check list — so it may list **only** `per_app`-scoped checks.
The `per_vm` checks and the position at which the per-app run happens still come from the shared
`tests/checks/manifest.yaml`. Use it for a recipe that cannot satisfy a default per-app check.
No recipe ships one today.

### Config-template variables are not script variables

The generated config declares a `[require_env]` block (`SERVERIP`, `RECIPE_NAME`,
`WORKFLOW_HOMEDIR`, `SSH_KEY_ABSPATH`, `AF_API_URL`, `AF_BOOTSTRAP_URL`, plus `BASE_DOMAIN`
when the generator is called with `--base-domain`). These are read from the **runner's**
environment and substituted into the config text — `src`, `dst`, `cmd`, `host` — before the SSH
session is opened. They are a config-templating mechanism only.

The `exec_vm` session declares no `env_*` keys, so the SSH executor propagates an empty
environment to the remote command. Nothing from `[require_env]` reaches the running script.
(The `exec_local` session is the opposite — it inherits the runner's whole environment — which
is why the old runner-side model could rely on `$SERVERIP`.)

A `${SERVERIP:-127.0.0.1}` fallback therefore always takes the fallback branch, and a
`${SERVERIP:?…}` assertion would hard-fail the script under `set -u`. Write `127.0.0.1`
directly.

## Location

```
recipes/<app-id>/health-check.sh
```

Required for every recipe that participates in live VM testing.

## Interface Contract

| Property | Requirement |
|----------|-------------|
| Shebang | `#!/usr/bin/env bash` |
| Options | `set -euo pipefail` |
| Arguments | None are passed. An optional `URL="${1:-<vm-correct-default>}"` is allowed for local debugging, but the default must be the value CI needs |
| Working directory | `/root` on the VM, the repo root on the docker leg — **never rely on it**, use absolute paths |
| Environment | Empty — assume no variables are set |
| Exit 0 | Application is healthy |
| Exit non-zero | Application is unhealthy — CI marks the test as failed |
| stdout/stderr | May print diagnostic output freely — it is captured and attached to the CI run |
| Network | Runs on the VM — target `127.0.0.1`, not a public IP |
| Execution time | Keep the total under **420 seconds** — the hard cap on the docker leg (`timeout 420`). The live leg sets no timeout of its own, but the same script runs on both |

The script must be **executable** (`chmod +x` or `755` in git):
```bash
git update-index --chmod=+x recipes/<app>/health-check.sh
```

## What to Check

Check the minimum that proves the application is running and reachable, addressed at the
loopback interface:

- **HTTP app**: `curl -sf "http://127.0.0.1:<port><path>"` returns HTTP 2xx
- **HTTPS app**: `curl -sfk "https://127.0.0.1:<port><path>"` (skip cert validation in test)
- **Non-HTTP app**: use `nc -z 127.0.0.1 <port>` or a protocol-specific client
- **App with no published host port** (routed via Traefik only): poll the container's own Docker
  healthcheck with `docker inspect` — see [Docker health polling](#docker-health-polling-no-published-port)

Do **not** test application logic or data — only reachability and a basic status response.

Available on the VM: `docker`, `docker compose`, `curl`, `nc`, and the installed recipe under
`/opt/<app>/` (`docker-compose.yml` and `.env`).

## Retry Pattern

Apps that take time to start (database migrations, certificate generation, image pulls) must
implement a wait loop. The CI workflow does not retry — if the script exits non-zero, the
test fails immediately.

```bash
#!/usr/bin/env bash
set -euo pipefail

MAX_WAIT=90
INTERVAL=5
ELAPSED=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -sf "http://127.0.0.1:<port>/<healthpath>" > /dev/null 2>&1; then
        echo "Healthy after ${ELAPSED}s"
        exit 0
    fi
    echo "Waiting... (${ELAPSED}s / ${MAX_WAIT}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: did not become healthy within ${MAX_WAIT}s"
exit 1
```

Use a `MAX_WAIT` that is realistic for the app but stays well under 420 s.
A simple HTTP app (already running) can skip the loop entirely.

## Relation to `metadata.yaml`

The `health_check` block in `metadata.yaml` documents the app's health endpoint for
informational and tooling purposes. `health-check.sh` should check the same endpoint:

```yaml
# metadata.yaml
health_check:
  type: http
  path: /healthz
  port: 5678
  timeout: 30
```

```bash
# health-check.sh — checks the same endpoint, on the VM's loopback
curl -sf "http://127.0.0.1:5678/healthz" > /dev/null 2>&1
```

## Examples

### Simple HTTP check (n8n)

```bash
#!/usr/bin/env bash
set -euo pipefail
curl -sf "http://127.0.0.1:5678/healthz" > /dev/null 2>&1
```

### HTTP check with wait loop (Traefik)

```bash
#!/usr/bin/env bash
set -euo pipefail

MAX_WAIT=60
INTERVAL=5
ELAPSED=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -sf "http://127.0.0.1:8080/ping" > /dev/null 2>&1; then
        echo "Healthy after ${ELAPSED}s"
        exit 0
    fi
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "Waiting... (${ELAPSED}s / ${MAX_WAIT}s)"
done

echo "ERROR: did not become healthy within ${MAX_WAIT}s"
exit 1
```

### Docker health polling (no published port)

Apps that publish no host port — everything reaches them through Traefik — cannot be curled on
the loopback. Wait for the container's own `HEALTHCHECK` (declared in `docker-compose.yaml`) to
report healthy instead. `recipes/wud/health-check.sh` is the reference implementation; the shape
is:

```bash
#!/usr/bin/env bash
set -euo pipefail

max_wait=300
waited=0
while [ $waited -lt $max_wait ]; do
  CONTAINER=$(docker ps --filter "name=<app>" --format "{{.Names}}" 2>/dev/null | head -1)
  if [ -n "$CONTAINER" ]; then
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "healthy" ]; then
      echo "<app> container is healthy"
      exit 0
    fi
  fi
  sleep 5
  waited=$((waited + 5))
done

echo "<app> health check timed out after ${max_wait}s"
exit 1
```

## Both invocation sites

The same script is run by two workflows, and **neither passes an argument**:

| Leg | Workflow | Where it runs | cwd | Loopback is |
|-----|----------|---------------|-----|-------------|
| Phase 1 (docker) | `test-recipes-docker.yaml` | the GitHub Actions runner, with the compose stack up on that runner | repo root | the runner — correct, the app is there |
| Phase 2 (live) | `test-recipes-live.yaml` | the test VM, uploaded to `/tmp/af-hc-<recipe>.sh` | `/root` | the VM — correct, the app is there |

`127.0.0.1` is the right target in both cases, which is why one script serves both. The
difference that does bite is cwd, so keep every path absolute.

## What the CI Workflow Does

1. Resolves a matching `af-api` branch (same-name with `main` fallback)
2. Triggers af-api `build.yaml` to build a per-branch image and pushes it to Harbor
3. Deploys af-api into the test cluster as a per-run Deployment + NodePort Service
4. Generates cloud-init for the recipe by calling the deployed `af-api`'s `/compose` endpoint
5. Provisions a CoreVPS test VM via the IF `ImageTester` tooling (`python-dwh-image-build-algorithm`)
6. Waits for SSH to become available on the VM
7. Generates the config for this combination with `scripts/gen-health-check-conf.py` — the
   sole definition of the suite — and runs it through `python-dwh-testsuite`. Most assertions
   run on the VM over the `exec_vm` SSH session:
    - SSH probes: once per VM (`test_docker_images`, `test_bootstrap_reachable`) and
      once per app (`test_install_dir_<app>`, `test_compose_file_persisted_<app>`,
      `test_env_file_persisted_<app>`)
    - Upload-and-execute of `health-check.sh`, once per app (`test_health_check_<app>`)
    - Traefik, only where they can mean something:
      `test_traefik_route_<app>` per app whenever a `base_domain` was sent to `/compose`;
      `test_traefik_le_staging_configured` when a `base_domain` was sent and the leg passes
      `--expect-le-staging` (every leg, since IF-1385 made staging per-request; it cats Traefik's
      compose file on the VM, and without a `base_domain` there is no Traefik to cat);
      `test_traefik_https_cert_issuer` additionally only for a single-app selection whose
      combination label equals that recipe id on a routable domain, because it runs on
      `exec_local` and curls `https://$RECIPE_NAME.$BASE_DOMAIN` from the runner
8. Tears down the VM and deletes the af-api Deployment + Service (even on failure)
9. Reports exit code as the PR status check result
