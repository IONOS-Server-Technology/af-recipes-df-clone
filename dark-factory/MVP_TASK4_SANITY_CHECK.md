Title: AF recipe sanity + runtime check: {{name}} ({{slug}})

Re-audit the already-`done` recipe `recipes/{{slug}}/` against everything
tasks 1-3 were supposed to get right, **then actually run it** — task 4
of the MVP build-now pipeline, and the last one before a human considers
flipping `enabled: true`. This exists because several real bugs shipped
through tasks 1-3 undetected this batch (a customer-facing password with
no delivery channel, invalid `categories` values, a broken
`health-check.sh` pattern, a UID-permission crash loop, an unquoted YAML
value AF's own bootstrap validator rejects, an app that silently binds to
the wrong host through Traefik) — no single earlier task's scope covered
catching them, no per-app reviewer saw the whole picture, and some of
these are simply invisible to a static read no matter how careful: they
only show up when the recipe is actually running. This task is both
passes, one app at a time — was originally two separate tasks (a static
audit and a separate VPS-install gate), merged after finding the static
half alone kept missing exactly the bugs the runtime half was built to
catch.

**Depends on tasks 1-3**: dispatch with `requires: [<task1 id>, <task2
id>, <task3 id>]` — this task reads the complete recipe, so nothing here
runs until `metadata.yaml`, the compose/install/health-check files, and
`logo.svg` all exist.

## Ground rule: fix small, escalate big

This task may fix **small, mechanical, low-risk issues in place** —
a wrong `categories` value, a missing `cap_drop`/`no-new-privileges`
line, a `health-check.sh` that doesn't handle the no-arg invocation, an
`app_min_ram_mb` that's obviously copy-pasted from the wrong template.
Commit and push those directly, the same as tasks 1-3 do.

It must **not** rewrite `install.sh`'s password handling, swap a
mechanism (`generated_from` ↔ `basic_auth` ↔ something else), redesign
`docker-compose.yaml`'s service topology, or make any other change whose
correctness isn't obvious from reading it once. For anything in that
class: **stop, do not commit, and escalate the issue to a human** instead
of attempting it:

```bash
curl -sS -X POST -H "Authorization: Bearer ${FACTORY_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${FACTORY_API_URL:-http://127.0.0.1:30080}/v1/issues/${QUEUE_ISSUE_ID}/transition" \
  -d '{"state":"human","message":"<exactly what you found and why it needs a human>"}'
```
Then stop working the issue — do not keep trying alternative fixes after
escalating. A clear, precise escalation is a complete, correct outcome for
this task, not a failure.

## What to do

1. **Password-delivery classification.** For every `type: password`
   parameter in `metadata.yaml`, re-derive which of the three mechanisms
   below actually covers it — don't trust the existing `description`
   text, verify against what `install.sh` and `docker-compose.yaml`
   actually do:
   - `generated_from` present, and confirm `install.sh` (or the app
     itself) writes that value into a field the app reads as an
     already-hashed credential — not into a plaintext-expecting field.
   - covered by this port's `basic_auth: true`.
   - genuinely internal (DB/JWT/session secret) — the app itself never
     shows this value to the customer, whatever `install.sh` generates
     for it independently.
   Any parameter that resolves to none of these is the exact bug class
   this task exists to catch — this is an architectural gap in the
   recipe, not a typo. **Escalate, don't fix.**

2. **Ports and connectivity.** Cross-check `metadata.yaml`'s `ports[]`
   against what `docker-compose.yaml` actually exposes: every port the
   compose file publishes has a matching `ports[]` entry (and vice versa —
   no `ports[]` entry for a port the compose file doesn't actually use);
   `http: true` is only set on a real HTTP(S) frontend; `basic_auth: true`
   is only set where step 1 needs it or the app genuinely has no login of
   its own; no raw database port (Postgres 5432, MySQL/MariaDB 3306,
   MongoDB 27017, Redis 6379, etc.) is marked `public: true` unless it's
   genuinely meant to be reachable (rare — flag and double check, don't
   assume the port number alone means it's wrong or right).

   **Default rule: any web UI port with no `generated_from`-covered
   credential should have `basic_auth: true`.** "Customer-known" means
   covered by a working `generated_from: "<algo>:ROOT_PASSWORD"` — not a
   randomly `install.sh`-generated password, not the app's own
   self-service signup/setup wizard, not an optional/blank-by-default
   site password. This covers every shape of "if a stranger loads this
   app's public URL right now, what can they do?" — an unclaimed setup
   wizard, a login-less dashboard/exporter/admin UI, or any other endpoint
   letting an anonymous visitor act before any credential exists.

   If a port fails this and the fix is just setting `basic_auth: true`
   (with a comment telling the customer to run `/root/auth.sh off
   {{slug}}` once they've claimed/configured the app — check an existing
   recipe with a similar auto-generated, non-customer-input password for
   the exact comment shape) and, if there was a now-pointless
   `install.sh`-generated parameter behind it, removing just that
   parameter and its generation step — that's a **small, mechanical
   fix**, do it directly, don't escalate.

   If the recipe instead auto-configures an app-specific credential via
   `docker-compose.yaml` env vars in a way that bypasses the app's own
   setup wizard entirely (so there's no wizard left for `basic_auth` to
   gate), fixing it means changing how the container is configured, not
   just `metadata.yaml`/`install.sh` — that crosses into "escalate, don't
   fix" territory. Flag it explicitly as "this app needs the same
   basic_auth default, but requires a compose-level change to get there"
   rather than leaving it unmentioned or attempting the change yourself.

3. **`health-check.sh` review.** Confirm it handles being invoked with
   **no arguments and no `$SERVERIP`** (the real invocation path in both
   `test-recipes-docker.yaml` and `tests/recipe-health-check.conf`) via
   the dual-mode `wait_for_healthy()` pattern already used by most of the
   catalogue (check 2-3 similar recipes for the reference shape) — not the
   `docs/health-check-spec.md` example's `$SERVERIP`-only form, which
   doesn't actually work for either real invocation path. Confirm it
   actually checks something meaningful (the app's real readiness
   endpoint / port, not just "the container is running").

   **Specifically check how the no-arg branch identifies its own
   containers — a widespread, confirmed-real bug in this exact spot.** If
   it derives the Compose project name from the script's own directory
   (something like `basename(dirname(BASH_SOURCE))`) and filters `docker
   ps` by that project label, **it is broken**: `test-recipes-docker.yaml`
   runs Compose with `--project-name "afpre-<recipe-id>"`, not the bare
   recipe id, so that filter matches zero containers and the script spins
   for the full timeout every time, regardless of whether the app itself
   is perfectly healthy. This passes every static read (the dual-mode
   shape looks right, `af-validate` has no rule for it) and only shows up
   by actually running it. If you find this pattern, it's a **small,
   mechanical fix** — replace the project-label filter with a
   boundary-anchored regex on the recipe's own slug: `--filter
   "name=(^|-){{slug}}-"`, **not** a bare substring (`--filter
   "name={{slug}}"`) — a bare substring is itself a confirmed real bug,
   since several recipe slugs are substrings of other, unrelated recipes'
   slugs, and `test-recipes-combinations.yaml` deploys multiple recipes on
   one host, so an unanchored filter can silently match another app's
   containers. Verify the fix for real: bring the stack up with `docker
   compose -p some-other-name up -d` (a project name that deliberately
   doesn't match the recipe's own directory), run `bash health-check.sh`
   with no arguments, and confirm it reports healthy — don't accept it on
   a read-through alone.

   **Separately, check `docker-compose.yaml`'s own `healthcheck:` block
   uses a tool that actually exists in that image — another confirmed
   real bug, found in 3 of 5 recipes checked in one batch (`curl` missing
   from a Node image and an Apache/PHP image).** This fails silently as
   "unhealthy forever" with no error in the app's own logs — easy to
   mistake for an app problem when it's actually just the wrong probe
   tool, and completely different from the container-discovery bug above
   (that one finds zero containers; this one finds the right container,
   which just never reports healthy). Confirm directly: `docker run --rm
   --entrypoint sh <image> -c "which <tool>"` against the actual image
   referenced in `docker-compose.yaml`. If missing, this is a **small,
   mechanical fix** — switch to whatever upstream's own reference
   healthcheck uses (check their compose file even if you're not using it
   for `compose_file_url` elsewhere), or another tool confirmed present
   in the image. Verify the replacement for real: `docker exec` the new
   test command into a running container and confirm exit 0, don't just
   assume it's right because it looks standard.

4. **Cross-file variable consistency.** There's no `af-validate` available
   here to run the real check (`af-api` is a separate, private repo this
   project's worker has no credentials for — don't try to fetch it), so
   this is a manual substitute for that class of check:
   - every env var `docker-compose.yaml` or `install.sh` reads has a
     literal value in `.env.template` (the `{{PARAM}}` placeholder
     mechanism was removed — IF-944 — so nothing should still look like
     a template placeholder).
   - every `generated_from` parameter name in `metadata.yaml` matches the
     variable name actually used in `.env.template`/`docker-compose.yaml`.
   - `id` in `metadata.yaml` matches the `recipes/{{slug}}/` directory
     name.

   **Every env var must be verified against the real upstream app, not
   just checked for internal consistency across our own files.** Matching
   across `metadata.yaml`/`.env.template`/`docker-compose.yaml` only
   proves earlier tasks agreed with each other — it doesn't prove the
   variable name, or the expected value shape (plaintext vs. a specific
   hash format), is something the app actually reads. Check the upstream
   image's real documentation, README, or (if undocumented) its
   Dockerfile/entrypoint script directly. If you cannot confirm a
   variable this way, say so explicitly in your report — don't assume it's
   correct just because it's consistent, and don't invent or guess a
   variable name yourself to "fix" one you can't verify. An unconfirmed
   variable whose behavior matters (anything password/auth-related
   especially) is a finding to escalate, not something to silently accept
   or silently patch.

5. **Mechanical schema rules.** `categories` uses only values from the
   fixed enum (`automation`, `ai`, `developer-tools`, `media`,
   `productivity`, `security`, `networking`, `storage`, `monitoring`,
   `home`, `communication`, `finance`, `education`, `gaming`,
   `utilities`, `infrastructure` — `database` is not one of them,
   `developer-tools` usually is the right fit). `app_version` is never
   the literal string `latest`, and matches whatever upstream's own
   compose file does (float if they float, pin if they pin — IF-1501).
   `recipe_version` is valid semver. These are small, safe to fix in
   place per the ground rule above.

6. **Structural hardening drift.** Compare `docker-compose.yaml` against
   2-3 similar existing recipes: does it set `cap_drop: [ALL]` and
   `security_opt: [no-new-privileges:true]` where those recipes do (skip
   only if the service genuinely needs a capability the comparison
   recipes don't use — say why); does it declare a compose-level
   `healthcheck:` block. Fix a missing one in place if adding it is a
   pure addition (doesn't change existing behavior); escalate if adding
   it would plausibly break the service (e.g. a capability it may
   actually need).

7. **Resource sizing sanity.** Check `app_min_ram_mb`/`app_min_disk_mb`
   against what `docker-compose.yaml` actually runs — a multi-service
   stack (its own Postgres/Redis/etc.) copy-pasting a single-container
   template's low value is the failure mode to catch. Adjust in place if
   clearly wrong; this is a number, not a design decision.

8. **Full runtime verification — NOT CURRENTLY DISPATCHABLE, DO NOT
   ATTEMPT THIS STEP AS A DARK-FACTORY WORKER.** Confirmed directly
   (2026-08-26): the coder worker image (`docker/Dockerfile.cc`) has no
   Docker — deliberately removed ("workers run as K8s Jobs with no
   Docker socket access... integration tests run against K8s-Pod backing
   services (M8) rather than docker compose"), and checking a real
   dispatched job's actual transcript confirmed no worker has ever run a
   `docker`/`docker compose`/`health-check.sh` command for this task,
   despite this step's own instructions telling it to. If you are a
   worker reading this: **skip step 8 entirely, do not claim to have
   verified it, do not fabricate output as if you had.** Restoring this
   is a real security decision, not a small config change — true
   Docker-in-Docker needs `--privileged` (or a cluster-level nested
   runtime like Sysbox, which a single pod can't opt into on its own),
   and mounting the host's Docker socket instead is arguably worse
   (equivalent to host root). The likely real fix is not "add Docker
   back" but redesigning this step around the K8s API directly (real
   sibling Pods as backing services, scoped by RBAC to a throwaway
   namespace — matching the `Dockerfile.cc` comment's own "M8" pointer)
   rather than `docker compose`. Until one of those lands, **step 8 is
   operator-only**: a human runs it by hand (as documented below), the
   same way it was done for the first recipe this step was designed
   against. The playground design itself is believed to be the right
   direction — what's missing is a way to actually execute it inside a
   worker's own sandbox.

   Steps 1-7 above remain fully dispatchable — they're pure file reads,
   no execution needed. Only step 8 is blocked.

   Everything here runs inside your own sandbox — no external VPS, no
   SSH, no credentials beyond what you already have (Docker + GitHub
   read access) — once a worker actually has that access.

   a. **Clean-state install.** In a scratch directory, copy
      `docker-compose.yaml`, `install.sh`, `health-check.sh`, and
      `.env.template` (as `.env`) from `recipes/{{slug}}/`. Run
      `bash install.sh`, then `docker compose -f docker-compose.yaml up
      -d`. Testing on top of already-initialized state hides exactly the
      class of bug (first-boot permissions, host binding) this step
      exists to catch — always start from nothing.

   b. **Confirm real health.** `bash health-check.sh` with no arguments.
      If any container never reaches healthy, `docker ps -a` + `docker
      logs` it and read the actual error — don't stop at "unhealthy,"
      find out why. A permission error writing to a bind-mounted data
      dir (the app's image runs as a fixed non-root UID your
      `install.sh` never `chown`'d) and a compose-level `restart: no`
      left unquoted (AF's bootstrap-side compose validator parses it as
      the YAML boolean `false` and rejects the file outright — quoting
      it as `restart: "no"` is not a reliable fix, since AF's `/compose`
      renderer can re-serialize the file and drop the quotes again; omit
      the key entirely instead, since Compose's own default when unset
      is already `"no"`) are both confirmed-real, both invisible to
      steps 1-7, and both **small, mechanical fixes** once found —
      don't escalate either.

   c. **Playground routing check.** If `metadata.yaml` has any `http:
      true` port, bring up the Traefik playground (exact spec below),
      attach the recipe's own service to it with the documented label
      contract, and confirm the app actually resolves through
      Host-header routing — not just that the container is healthy.
      This is the step that catches an app silently bound to the wrong
      hostname: confirmed real on a recipe whose own "deployment
      identity" defaulted to `localhost` unless told its real public
      domain via an env var, so every request through Traefik 404'd
      even though the container itself was perfectly healthy — nothing
      in steps 1-7 or step 8b would ever have caught that, only an
      actual Host-header request through a real router does. If the app
      exposes a browser-facing UI, also check with a browser-shaped
      `Accept: text/html` header specifically — some apps only serve
      their web UI conditionally on a separate feature flag, defaulting
      to a raw API/JSON response otherwise, which passes every other
      check here while still being useless to an actual customer.

      This does **not** replace CI's `Test Recipes Live` — the
      playground has no TLS/cert-manager and a fake domain, so it
      proves the recipe's own host-binding/routing logic works, not the
      full AF bootstrap. If step 8c fails and the fix is a
      `docker-compose.yaml` env var (matching the shape of the two
      confirmed examples above: a "what's my public URL" var, a "serve
      the UI, not just the API" flag), that's still a **small,
      mechanical fix** — set it, re-run steps 8a-8c clean, done. If
      fixing it would mean redesigning how the app is configured or
      deployed, escalate instead.

   d. Leave the stack running (don't tear it down) — the next thing to
      look at, if something's still wrong, is easier debugged live than
      re-derived from a report.

### Docker playground reference

A one-off, disposable Traefik you stand up yourself for step 8c — not a
shared or persistent service, not the real AF stack. Skips TLS entirely
(HTTP only, `entrypoints.web`) since this step is about host-routing
logic, not certificates; `Test Recipes Live` in CI is what validates the
real TLS/cert-manager path.

```yaml
# playground/docker-compose.yaml
services:
  traefik:
    image: traefik:v3.7.10
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
    ports:
      - "18080:80"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - traefik-net
networks:
  traefik-net:
    name: traefik-net
    driver: bridge
```

Attach the recipe's own service to this network and add the label
contract AF's real `/compose` renderer produces (confirmed against a live
rendered recipe; this is the one part of the real bootstrap this
playground does reproduce, since it's exactly what step 8c needs):

```yaml
  {{slug}}:
    # ...existing service definition...
    labels:
      - traefik.enable=true
      - traefik.http.routers.{{slug}}.rule=Host(`{{slug}}.playground.test`)
      - traefik.http.routers.{{slug}}.entrypoints=web
      - traefik.http.services.{{slug}}.loadbalancer.server.port=<the
        app's own http port, from metadata.yaml ports[]>
      - traefik.docker.network=traefik-net
    networks:
      - <the recipe's own network(s)>
      - traefik-net
```

Set `AF_APP_DOMAIN={{slug}}.playground.test` in `.env` (real AF sets this
to the actual per-app subdomain — the playground fakes it the same
shape). Test with `curl --resolve
{{slug}}.playground.test:80:127.0.0.1 http://{{slug}}.playground.test:18080/`
— `--resolve` fakes the DNS, no real domain needed.

9. Commit and push any in-place fixes from steps 5-8 (and 2/3/4 where the
   fix is similarly small and obvious) as one commit. If nothing needed
   fixing, that's a valid outcome — say so in the report, don't invent
   busywork.

## Report back — always

State explicitly, one line per numbered step above (including 8a-8d):
what you checked, what you found (including "nothing wrong" — don't skip
a step silently), and whether you fixed it, left it (explain why), or
escalated it to `human` (quote the exact message you sent). For step 8:
confirm you actually ran it clean (not just read the files) and, if you
reached 8c, state explicitly whether the app has an `http: true` port and
if so what the playground request returned. If you escalated, say so
prominently at the top of the report, not buried at the end.

## This is enforced, not just requested — mostly

Everything above except step 1's mechanism-correctness judgment, step 6's
"does this service genuinely need the capability" judgment, and step 8's
"is this a small env-var fix or a redesign" judgment is a mechanical,
checkable rule — treat any uncertainty there as a reason to escalate, not
a reason to guess. There is no CI job that re-runs steps 1-7; step 8 is
the closest thing to CI's own `Test Recipes Live` this task has, but it's
still not a substitute — it runs once, in a simplified environment, not
on every future change. This is exactly why the ground rule above (fix
small, escalate big) exists — a wrong guess here has no second gate to
catch it before a human considers `enabled: true`.
