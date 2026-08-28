Title: AF recipe compose+install: {{name}} ({{slug}})

Write `docker-compose.yaml`, `.env.template`, `install.sh`, and
`health-check.sh` under `recipes/{{slug}}/` for "{{name}}" — task 2 of the
MVP build-now pipeline. `recipes/{{slug}}/metadata.yaml` already exists
(task 1) and is a fixed input here: ports and parameters are already
decided there, this task implements them, it does not re-decide them. Do
not edit `metadata.yaml`.

If `recipes/{{slug}}/metadata.yaml` doesn't exist, stop immediately and
report that instead of proceeding — that means task 1 hasn't landed yet.

## What to do

1. Read `recipes/{{slug}}/metadata.yaml` in full. `ports[]` and
   `parameters[]` are fixed — every service you expose and every credential
   you wire up must match them exactly, not something you re-derive from
   upstream yourself.

2. Read `.claude/skills/af-create-recipe/SKILL.md` Phase 2 (Research),
   Phase 3 (Plan), and Phase 4 (Generate + Self-Check against RFC-002) —
   that skill is the actual generation method and self-check loop for this
   task (pick a structural template from 2-3 similar existing recipes,
   write the files, walk `rfc/002-recipe-rules.md` rule-by-rule reporting
   `✓`/`✗ ERROR`/`⚠ WARN` per slug, patch and re-check until zero ERRORs).
   Use `apps-gaps/{{slug}}.yaml` (`upstream.url`, `upstream.docker_image`,
   `upstream.compose_file_url`/`compose_file_notes`) as your research base
   per that Phase 2, same as task 1 did.

   Where this task differs from a full Phase 1-5 run:
   - `metadata.yaml` already exists (task 1) — skip writing it, and don't
     re-decide `ports[]`/`parameters[]`/`app_version`; wire the compose
     file, `.env.template`, and `install.sh` to match what's already there
     exactly, including task 1's float-vs-pin choice on `app_version`
     (IF-1501 — this task doesn't re-litigate it).
   - Only generate `docker-compose.yaml`, `.env.template`, `install.sh`,
     `health-check.sh` — not `logo.svg` (task 3) and not `metadata.yaml`.
   - Self-check only against §3.1, §3.4 (parameters), and §3.5 of
     `rfc/002-recipe-rules.md` — skip §3.2 (metadata) and §3.3 (logo),
     neither of which this task's files touch. There's no local copy of
     `af-api`'s validator to cross-check against (`af-api` is a separate,
     private repo this project's worker has no credentials for) — this
     manual RFC-002 pass is the check available here; task 4
     (`af-validate`) is the independent second opinion, not this task's
     job.

3. **Never write `restart: "no"` (or unquoted `restart: no`) in
   `docker-compose.yaml` — omit the `restart` key entirely instead.**
   Confirmed real bug, found and fixed twice before landing on this: an
   unquoted `no` parses as the YAML *boolean* `false`, which AF's
   bootstrap-side compose validator rejects (`services.<name>.restart must
   be a string`) — and quoting it (`restart: "no"`) does **not** reliably
   fix this, because AF's `/compose` renderer re-serializes the file
   through a YAML library that can drop the quotes again on the way to
   the bootstrap archive, independent of what the source file says. None
   of this shows up in `af-validate`, a local `docker compose up`, or the
   Docker-only CI leg — only a real VM install hits it. Compose's own
   default restart policy when the key is omitted is already `"no"`, so
   just don't declare it for a one-shot/init service — it's the only
   value in this situation that's both correct and unambiguous.

4. **`health-check.sh`: do NOT copy `docs/health-check-spec.md`'s own
   "Retry Pattern" example verbatim — it's `$SERVERIP`-only and will fail
   both real test paths.** Confirmed by reading the actual invocation code,
   not just the doc: `test-recipes-docker.yaml` runs `bash health-check.sh`
   with no arguments and never sets `$SERVERIP` at all; the live-VM harness
   (`tests/recipe-health-check.conf`'s `test_health_check`) uploads the
   script *to the VM* and runs it there over SSH, no arguments either — so
   in both real cases the script must work with **no argument and no
   `$SERVERIP`**, checking its own local Docker container state. A script
   that does `: "${SERVERIP:?...}"` up front (the doc's own example) aborts
   immediately in both. Use the dual-mode pattern instead — no-arg branch
   waits on local container state, optional arg/`$SERVERIP` branch is only
   a manual/secondary path.

   **Do not default to `curl` in a service's own `healthcheck:` block —
   confirmed real bug, found in 3 of 5 recipes checked in one batch, so
   treat it as a systemic risk, not an edge case.** Several images (a
   Node service, an Apache/PHP service, among others) simply don't have
   `curl` installed — the healthcheck then fails every single attempt
   with "command not found," reporting the container `unhealthy` forever
   even though the app itself started and is running completely fine.
   This never shows up as an app-level error in the logs, only as an
   endless "unhealthy" status, which is easy to misdiagnose as an app
   startup problem when it's actually just the wrong probe tool. Verify
   the tool actually exists before writing a `healthcheck:` test: check
   upstream's own reference compose file first (their choice is the
   strongest signal — if they use a bundled script, use that same one),
   and if unclear, confirm directly with `docker run --rm --entrypoint sh
   <image> -c "which curl"` (or whatever tool you're about to use) against
   the real image before trusting it.

   **Never capture a shell variable inside a `healthcheck: test:
   ["CMD-SHELL", ...]` string — confirmed real bug.** A multi-statement
   probe like `out=$(wget ...); st=$?; case "$out" in ...)` looks fine
   because it works when you run it directly in the container with `docker
   exec`/`podman exec`. But `docker compose` parses `docker-compose.yaml`
   through its *own* variable-interpolation pass before the string ever
   reaches the container — any bare `$name` in the file (not just in
   `environment:`, anywhere, including inside a `test:` string) is treated
   as compose's own substitution syntax. Since `out`/`st` aren't compose
   variables, compose silently blanks them to empty (`docker compose
   config` will show a warning: `The "out" variable is not set. Defaulting
   to a blank string.`), so the shell never sees what you wrote — it sees
   `[ -eq 0 ]` and `case "" in ...`, which fails every single time,
   forever. This will pass any test you run by directly `exec`-ing into a
   container, and only fails once something actually runs the recipe
   through real `docker compose`/`docker-compose up` — verify healthchecks
   that way, not just with `docker exec`. If you need to inspect a
   command's output/exit code, pipe it (`... | grep -q pattern`) instead of
   capturing it into a variable — a pipeline has nothing for compose to
   interpolate.

   **A healthcheck probe's expected response can differ between an
   ephemeral test run and the recipe's real, persistent bind-mounted data
   dir — confirmed real bug.** An app that isn't yet configured (its
   `install.sh` doesn't finish onboarding, leaving the setup wizard for the
   customer) can behave differently depending on whether its data
   directory already has some baked-in default content (no volume, or the
   image's own overlay) versus a genuinely empty external bind mount — one
   app returned a clean `401 Unauthorized` in the former case and an
   uncaught server-side exception (`200` with an error page) in the
   latter, for the exact same endpoint. Test the healthcheck against the
   *actual* mount shape `install.sh`/`docker-compose.yaml` declare, not an
   image run with no volume at all. When an app's unconfigured-state
   response isn't reliably a specific status code, don't match on one —
   check only that a response arrived at all (e.g. grep for `HTTP/1.1` in
   `wget -S`'s output) and let a refused/timed-out connection be the only
   failure signal.

   **Do not derive the Compose project name from this script's own
   directory and filter `docker ps` by that project label — this is
   confirmed broken and does not just look risky.** `test-recipes-docker.yaml`
   invokes Compose with `--project-name "afpre-<recipe-id>"`, not the bare
   recipe id, so a project-label filter computed as
   `basename(dirname(BASH_SOURCE))` never matches any container, the wait
   loop spins on zero containers for the full timeout, and the recipe fails
   its actual CI docker test — while still looking completely correct to a
   static read, since the dual-mode *shape* is right and nothing here is
   caught by schema validation. **Instead, filter `docker ps` by container
   name using a boundary-anchored regex on this recipe's own slug** —
   `--filter "name=(^|-){{slug}}-"`, not a bare substring. Every container
   Compose creates is named `<project>-<service>-<index>`, and the project
   name always contains the recipe's own slug regardless of whatever
   prefix a given harness uses, so this matches robustly across all of
   them — but a bare substring filter (`--filter "name={{slug}}"`) is a
   **confirmed real bug**, not a theoretical one: several existing recipe
   slugs are substrings of others (a short slug matching inside a longer,
   unrelated one), and `test-recipes-combinations.yaml` deploys multiple
   recipes together on one host, so an unanchored filter can silently pick
   up another app's containers. The anchored form only matches the slug at
   a project/service name boundary. Verify this for real before finishing:
   bring the stack up locally with `docker compose -p
   "some-other-project-name" up -d` (a project name that does **not** match
   `{{slug}}`'s directory), then run `bash health-check.sh` with no
   arguments and confirm it reports healthy — don't just read the script
   and assume the logic is right.

5. Commit `docker-compose.yaml`, `.env.template`, `install.sh`, and
   `health-check.sh` under `recipes/{{slug}}/` — no other files, and don't
   touch `metadata.yaml`. Push normally; there's no PR to open (dark-factory
   has no PR concept — a verified push to `main` is what "done" means
   here). `enabled: false` on `metadata.yaml` already keeps this
   non-customer-visible regardless of when it lands.

## Report back — always, even if nothing was written

State explicitly, so a human can review without re-deriving your work:
- which template recipe(s) you modeled the 4 files on and why
- the RFC-002 self-check output (step 2's line-per-rule list)
- anything from `metadata.yaml`'s `ports[]`/`parameters[]` you could NOT
  cleanly wire into the compose file or `.env.template` — report it, don't
  paper over it
- whether `health-check.sh` uses `$SERVERIP` correctly (confirm you read
  `docs/health-check-spec.md`, don't just assert it)

## This is enforced, not just requested

The `af-validate-rfc002` CI job and `test-recipes-docker.yaml` both run
against whatever lands on `main` — step 2's self-check catches the same
class of problem early, it doesn't replace either gate. Task 4
(`af-validate`) and Task 5 Phase 1 (`test-recipes-docker.yaml`) are
dispatched as separate issues once this one is done, `requires`-gated on
this issue's id.
