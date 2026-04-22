# Health Check Spec — `health-check.sh`

## Purpose

`health-check.sh` is a **CI-only script** run by the live test workflow after a recipe is
installed on a test VM. It verifies that the application is actually reachable and healthy.

It is **not** deployed to production VMs and is **separate** from Docker Compose healthchecks
(which are declared in `docker-compose.yml` and govern container restarts).

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
| Network | Runs on the test VM; `localhost` resolves to the VM itself |
| Execution time | Must exit within **120 seconds** (CI workflow timeout per recipe) |

The script must be **executable** (`chmod +x` or `755` in git):
```bash
git update-index --chmod=+x recipes/<app>/health-check.sh
```

## What to Check

Check the minimum that proves the application is running and reachable:

- **HTTP app**: `curl -sf http://localhost:<port><path>` returns HTTP 2xx
- **HTTPS app**: `curl -sfk https://localhost:<port><path>` (skip cert validation in test)
- **Non-HTTP app**: use `nc -z localhost <port>` or a protocol-specific client

Do **not** test application logic or data — only reachability and a basic status response.

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
    if curl -sf http://localhost:<port>/<healthpath> > /dev/null 2>&1; then
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
# health-check.sh — checks the same endpoint
curl -sf http://localhost:5678/healthz > /dev/null 2>&1
```

## Examples

### Simple HTTP check (n8n)

```bash
#!/usr/bin/env bash
set -euo pipefail
curl -sf http://localhost:5678/healthz > /dev/null 2>&1
```

### HTTP check with wait loop (Traefik)

```bash
#!/usr/bin/env bash
set -euo pipefail

MAX_WAIT=60
INTERVAL=5
ELAPSED=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if curl -sf http://localhost:8080/ping > /dev/null 2>&1; then
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

1. Provisions a CoreVPS test VM via IONOS Cloud API
2. Injects cloud-init rendered by `scripts/render-cloudinit.py` (using `test-params.yaml` defaults)
3. Waits for SSH to become available
4. Copies and executes `health-check.sh` on the VM via SSH
5. Tears down the VM (even on failure)
6. Reports exit code as the PR status check result
