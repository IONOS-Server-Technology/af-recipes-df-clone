# Health Check Spec — `health-check.sh`

## Purpose

`health-check.sh` is a **CI-only script** run by the live test workflow after a recipe is
installed on a test VM. It verifies that the application is actually reachable and healthy.

It is **not** deployed to production VMs and is **separate** from Docker Compose healthchecks
(which are declared in `docker-compose.yml` and govern container restarts).

## Where the script runs — IMPORTANT

The script is invoked from `tests/recipe-health-check.conf` as a `Plugins.Shell.Test` with
`executors = exec_local`. That means **`health-check.sh` runs on the GitHub Actions runner,
not on the test VM**. The runner exec'es `bash $WORKFLOW_HOMEDIR/recipes/$RECIPE_NAME/health-check.sh`
locally while the application stack is running on the remote VM.

Consequences:

- `localhost` inside the script resolves to the **runner**, not the VM. A naive
  `curl http://localhost:5678/healthz` hits the runner (which has nothing listening)
  and silently fails.
- To reach the application, use the `$SERVERIP` env var that the test framework injects
  (the VM's public IPv4). Example: `curl -sf "http://${SERVERIP}:5678/healthz"`.
- VM-side checks that need a shell on the VM (filesystem layout, `docker images`,
  `systemctl status …`) belong in the `.conf` file as `Plugins.Ssh.Test` entries with
  `executors = exec_vm`, not in `health-check.sh`. See `tests/recipe-health-check.conf`
  for the existing examples (`test_install_dir`, `test_docker_images`,
  `test_bootstrap_reachable`).

> **Known follow-up:** the existing recipes in this repository (n8n, portainer, …) still
> use `curl http://localhost:<port>` because the original spec described the script as
> VM-side. Those scripts currently no-op against an empty runner and need to be
> retargeted to `$SERVERIP`. Tracked separately — do not add new recipes that use
> `localhost`.

## Env vars available to the script

The test framework guarantees the following env vars are set before invocation
(declared in `tests/recipe-health-check.conf` `[require_env]`):

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
| Arguments | None — script takes no arguments |
| Working directory | Unspecified — do not rely on it |
| Exit 0 | Application is healthy |
| Exit non-zero | Application is unhealthy — CI marks the test as failed |
| stdout/stderr | May print diagnostic output freely — it is captured and attached to the CI run |
| Network | Runs on the runner — use `$SERVERIP` to reach the VM, **not** `localhost` |
| Execution time | Must exit within **120 seconds** (CI workflow timeout per recipe) |

The script must be **executable** (`chmod +x` or `755` in git):
```bash
git update-index --chmod=+x recipes/<app>/health-check.sh
```

## What to Check

Check the minimum that proves the application is running and reachable. The script runs
on the runner, so all probes must target `$SERVERIP` (the VM), not `localhost`:

- **HTTP app**: `curl -sf "http://${SERVERIP}:<port><path>"` returns HTTP 2xx
- **HTTPS app**: `curl -sfk "https://${SERVERIP}:<port><path>"` (skip cert validation in test)
- **Non-HTTP app**: use `nc -z "$SERVERIP" <port>` or a protocol-specific client

Do **not** test application logic or data — only reachability and a basic status response.

## Retry Pattern

Apps that take time to start (database migrations, certificate generation, image pulls) must
implement a wait loop. The CI workflow does not retry — if the script exits non-zero, the
test fails immediately.

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${SERVERIP:?SERVERIP must be set by the test framework}"

MAX_WAIT=90
INTERVAL=5
ELAPSED=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -sf "http://${SERVERIP}:<port>/<healthpath>" > /dev/null 2>&1; then
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

Use a `MAX_WAIT` that is realistic for the app but stays well under 120 s.
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
# health-check.sh — checks the same endpoint, addressed at the VM
curl -sf "http://${SERVERIP}:5678/healthz" > /dev/null 2>&1
```

## Examples

### Simple HTTP check (n8n)

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${SERVERIP:?SERVERIP must be set by the test framework}"
curl -sf "http://${SERVERIP}:5678/healthz" > /dev/null 2>&1
```

### HTTP check with wait loop (Traefik)

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${SERVERIP:?SERVERIP must be set by the test framework}"

MAX_WAIT=60
INTERVAL=5
ELAPSED=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -sf "http://${SERVERIP}:8080/ping" > /dev/null 2>&1; then
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
    - Runner-side `Plugins.Shell.Test` invocation of `health-check.sh` with `$SERVERIP` injected
8. Tears down the VM and deletes the af-api Deployment + Service (even on failure)
9. Reports exit code as the PR status check result
