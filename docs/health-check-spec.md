# Health Check Spec — `health-check.sh`

## Purpose

`health-check.sh` is a **CI-only script** run by the live test workflow after a recipe is
installed on a test VM. It verifies that the application is actually reachable and healthy.

It is **not** deployed to production VMs and is **separate** from Docker Compose healthchecks
(which are declared in `docker-compose.yml` and govern container restarts).

## Where the script runs — IMPORTANT

The script is declared in `tests/recipe-health-check.conf` as a `Plugins.UploadExecute.Test`
with `executors = exec_vm`. The test framework **uploads the script to the VM and executes it
there**. `health-check.sh` runs on the test VM itself, not on the GitHub Actions runner.

Consequences:

- `localhost` and `127.0.0.1` inside the script resolve to the **VM**, not the runner.
  `docker`, `docker compose`, and `docker exec` are available.
- To reach the application via a host-published port, use `localhost` or `127.0.0.1`. For
  recipes whose port is routed through Traefik and **not** published on the host (base_domain
  renders), use `docker exec` to probe from inside the container instead.
- VM-side checks that need SSH from the runner (filesystem layout, `docker images`,
  `systemctl status …`) belong in the `.conf` file as `Plugins.Ssh.Test` entries, not in
  `health-check.sh`. See `tests/recipe-health-check.conf` for examples.

## Env vars available to the script

The test framework guarantees the following env vars are set in the **runner environment**
(declared in `tests/recipe-health-check.conf` `[require_env]`). They are used for conf
interpolation and exec_local tests. They are **not** automatically exported into the VM shell
when `health-check.sh` runs via `exec_vm` — do not reference them inside the script.

| Var | Meaning |
|-----|---------|
| `SERVERIP` | Public IPv4 of the test VM |
| `RECIPE_NAME` | The recipe currently under test |
| `WORKFLOW_HOMEDIR` | Absolute path to the `af-recipes` checkout on the runner |
| `SSH_KEY_ABSPATH` | Path to the private SSH key for the VM (RSA, root) |
| `AF_API_URL` | URL of the af-api Service exposed for this run (per-branch deployment) |

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
| Arguments | Optional URL to probe; no-arg invocation must use `docker exec` for base_domain renders |
| Working directory | Unspecified — do not rely on it |
| Exit 0 | Application is healthy |
| Exit non-zero | Application is unhealthy — CI marks the test as failed |
| stdout/stderr | May print diagnostic output freely — it is captured and attached to the CI run |
| Network | Runs on the VM — `localhost`/`127.0.0.1` is the VM; use `docker exec` for unpublished ports |
| Execution time | Must exit within **300 seconds** |

The script must be **executable** (`chmod +x` or `755` in git):
```bash
git update-index --chmod=+x recipes/<app>/health-check.sh
```

## What to Check

Check the minimum that proves the application is running and reachable. The script runs on
the VM, so `localhost`/`127.0.0.1` reaches host-published ports directly:

- **HTTP app**: `curl -sf "http://127.0.0.1:<port><path>"` returns HTTP 2xx
- **HTTPS app**: `curl -sfk "https://127.0.0.1:<port><path>"` (skip cert validation in test)
- **Unpublished port** (base_domain render): use `docker exec <container> curl …` to probe from inside the container
- **Non-HTTP app**: use `nc -z 127.0.0.1 <port>` or a protocol-specific client

Do **not** test application logic or data — only reachability and a basic status response.

## Retry Pattern

Apps that take time to start (database migrations, certificate generation, image pulls) must
implement a wait loop. The CI workflow does not retry — if the script exits non-zero, the
test fails immediately.

```bash
#!/usr/bin/env bash
set -euo pipefail

MAX_WAIT=120
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

Use a `MAX_WAIT` that is realistic for the app but stays well under 300 s.
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
# health-check.sh — checks the same endpoint
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

## What the CI Workflow Does

1. Resolves a matching `af-api` branch (same-name with `main` fallback)
2. Triggers af-api `build.yaml` to build a per-branch image and pushes it to Harbor
3. Deploys af-api into the test cluster as a per-run Deployment + NodePort Service
4. Generates cloud-init for the recipe by calling the deployed `af-api`'s `/compose` endpoint
5. Provisions a CoreVPS test VM via the IF `ImageTester` tooling (`python-dwh-image-build-algorithm`)
6. Waits for SSH to become available on the VM
7. Runs `tests/recipe-health-check.conf` through `python-dwh-testsuite`:
    - VM-side SSH probes (`test_install_dir`, `test_docker_images`, `test_bootstrap_reachable`)
    - `Plugins.UploadExecute.Test` invocation of `health-check.sh` on the VM (`exec_vm`)
8. Tears down the VM and deletes the af-api Deployment + Service (even on failure)
9. Reports exit code as the PR status check result
