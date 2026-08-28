# Using the dark-factory REST API from Claude Code

Operator-side reference for how we've actually been driving factoryd from a
shell (curl + jq), built up across the fibonacci-rest-api and
recipe-catalogue sessions. Not part of any dark-factory repo — this is our
own cheat sheet.

## Two different API surfaces — don't mix them up

factoryd exposes two distinct sets of routes that look similar but need
completely different auth:

- **`/v1/*` — the real JSON API.** Accepts `Authorization: Bearer
  <FACTORY_API_TOKEN>`. This is what `scripts/queue.sh` itself calls under
  the hood, and what you should use from curl.
- **Everything else (`/issues`, `/projects-form`, `/settings`,
  `/settings/llm-token`, …) — server-rendered web-form endpoints.** These
  require a *browser session cookie* from logging in at `/settings` or the
  main UI. Hitting them with just a bearer token silently 302-redirects to
  `/login` — no error, just a redirect, easy to miss.

Rule of thumb: if the path doesn't start with `/v1/`, it's a web-UI route
and curl+bearer won't work. Use the UI, or find the `/v1/` equivalent.

## Getting the bearer token

It's a k8s Secret in the `dark-factory` namespace (`factory-secret`, key
`FACTORY_API_TOKEN`) — ask a teammate with cluster access for the exact
`kubectl get secret` incantation, then store it once per session:

```bash
FACTORY_API_TOKEN=<fetched via kubectl, see above>
API=http://<cluster-ip>:30080   # NodePort 30080
```

## Projects

```bash
# List projects
curl -sS -H "Authorization: Bearer $FACTORY_API_TOKEN" "$API/v1/projects"
```

Response includes `id`, `name`, `repo_url`, `repo_branch`,
`deploy_key_overridden` (bool — false means it's using the factory-wide
default key, not a per-project one), `llm_token_overridden`.

Creating a project via the API mirrors `queue.sh project add`'s body shape
(`{label, repo_url, repo_branch, key_file (as content), llm_token}`), but we
mostly did this through the web UI in practice — easier to register the
per-project deploy key from the same panel that generates it.

## Issues

**Create** — note the endpoint is `/v1/issues`, NOT `/issues` (that's the
web-form one):

```bash
BODY=$(jq -n \
  --arg label "some label" \
  --arg desc "full description text" \
  --argjson requires '[1,2]' \
  --argjson project_id 2 \
  '{label: $label, description: $desc, requires: $requires, project_id: $project_id}')

curl -sS -X POST -H "Authorization: Bearer $FACTORY_API_TOKEN" -H "Content-Type: application/json" \
  "$API/v1/issues" -d "$BODY"
# => {"id": 7}
```

Always build the JSON body with `jq -n`, not manual string interpolation —
descriptions routinely contain quotes/backticks/newlines that break naive
shell quoting.

**Read** (full detail — comments, jobs, mrs, attachments):

```bash
curl -sS -H "Authorization: Bearer $FACTORY_API_TOKEN" "$API/v1/issues/5" | jq .
```

**Transition status** — the field name is **`state`**, not `status` or
`to`. Getting this wrong doesn't 404 or 400 with a helpful message about the
missing field — it silently binds an empty string and you get back
`{"error":"invalid state: \"\""}`, which looks like *your value* was
rejected rather than the field name being wrong:

```bash
curl -sS -X POST -H "Authorization: Bearer $FACTORY_API_TOKEN" -H "Content-Type: application/json" \
  "$API/v1/issues/8/transition" -d '{"state":"pending"}'
# => {"id":8,"from":"human","to":"pending"}
```

Valid states (from `store.IsValidStatus`): `pending`, `coding`,
`pending_review`, `reviewing`, `pending_supervisor`, `supervising`, `done`,
`human`, `rejected`. Not every transition is legal from every state —
check `backend/internal/store/transitions.go` in the dark-factory-go-ts repo
if a transition gets rejected unexpectedly.

## Job logs

```bash
# Raw stream-json (what the worker actually produced)
curl -sS -H "Authorization: Bearer $FACTORY_API_TOKEN" "$API/v1/jobs/14/logs?format=raw"

# jsonl format + follow (what queue.sh logs -f uses, piped through logview.jq for readability)
curl -sS -N -H "Authorization: Bearer $FACTORY_API_TOKEN" "$API/v1/jobs/14/logs?format=jsonl&follow=true"
```

Once a job's k8s Pod is garbage-collected (`ttlSecondsAfterFinished: 60`),
factoryd transparently falls back to the archived Loki copy — same
endpoint, no code change needed on our end, `-f`/follow just won't work
against the Loki fallback.

## Factory-wide settings (concurrency, retries, escalations)

`GET`/`PATCH /v1/settings` — factory-wide defaults, distinct from the
per-project `max_retries` override on `/v1/projects/:id` (see above; a
project's own value, when set, wins over these):

```bash
curl -sS -H "Authorization: Bearer $FACTORY_API_TOKEN" "$API/v1/settings"
# => {"default_worker_image":"...","max_retries":2,"max_escalations":2,"max_concurrent_jobs":4}

curl -sS -X PATCH -H "Authorization: Bearer $FACTORY_API_TOKEN" -H "Content-Type: application/json" \
  "$API/v1/settings" -d '{"max_concurrent_jobs": 2}'
```

Unlike the per-project `max_retries` PATCH, this one wants a real JSON int,
not a string. Also read fresh every reconcile tick (no `factoryd` restart
needed), but only gates *new* job launches — pods already running when you
lower it keep running; the count tapers down as they finish rather than
getting killed. Useful to throttle throughput to survive a shared
Anthropic quota overnight without babysitting it.

## Checking which model actually ran a job

The pod's `CLAUDE_WORKER_MODEL`/`CLAUDE_WORKER_EFFORT` env vars are often
useless to inspect after the fact — the pod is usually already
garbage-collected (`ttlSecondsAfterFinished: 60`) by the time you go look,
and even when it's still around the value is empty string for the default
(non-opus) case rather than an explicit model name. The reliable source is
the job's own logs, which always record what was actually used:

```bash
jobid=$(curl -sS -H "Authorization: Bearer $FACTORY_API_TOKEN" "$API/v1/issues/<id>" | jq -r '.jobs[-1].id')
curl -sS -H "Authorization: Bearer $FACTORY_API_TOKEN" "$API/v1/jobs/$jobid/logs?format=raw" \
  | grep -o '"model":"[a-z0-9-]*"' | sort -u
```

## Things that live in k8s Secrets, not the API

Some credentials are genuinely only readable via `kubectl`, not any HTTP
endpoint we found (the equivalent web-form pages are session-only, and
there's no `/v1/` route that returns raw secret material — reasonably, by
design):

- The Anthropic key currently wired into workers: Secret `worker-anthropic`,
  key `ANTHROPIC_API_KEY`.
- The factory-wide default SSH deploy key: Secret `worker-ssh`, keys are
  `id_ed25519` / `id_ed25519.pub` (not `deploy_key*`).

Fetch either with `kubectl get secret <name> -o jsonpath='{.data.<key>}' |
base64 -d` if you have cluster access.

If a project has `deploy_key_overridden: true`, the *actual* key used at
dispatch time is per-project, not in `worker-ssh` — we never found a clean
`kubectl`-only way to fetch a per-project override; the settings UI panel is
the reliable path for that one.

## Querying the queue database directly (read-only, for debugging)

When the API doesn't expose something conveniently (e.g. `retry_count`
isn't visible in most `/v1/issues/:id` summaries the way you'd want for a
quick board-wide check):

```bash
kubectl -n dark-factory exec deploy/postgres -- psql -U factory -d factory \
  -c "select id, label, status, retry_count from issue where project_id=2 order by id;"
```

User is `factory`, database is `factory` (not `postgres`/`dark_factory` —
easy to guess wrong).

## Practical gotchas encountered

- **Rate-limit 429s from the Anthropic workspace are usually transient**,
  not a broken credential — check if other issues from the same burst
  succeeded before assuming the key is wrong. Re-verify the actual key value
  in `worker-anthropic` against `.secrets/anthropic_api_key` before
  concluding it's a bad-key problem specifically.
- **The "last retry escalates to opus" behavior** (`launcher.go`:
  `if issue.RetryCount >= maxRetries { claudeModel, claudeEffort = "opus",
  "medium" }`) triggers based on the issue's *stored* `retry_count`, which
  doesn't reset just because you manually transitioned it back to
  `pending` — a previously-escalated issue can dispatch on opus again even
  when the actual problem (e.g. a bad API key) has nothing to do with
  difficulty.
  **Fix without touching Postgres or recreating issues:** `maxRetries` is
  read via `Store.GetMaxRetries`, which returns the *project's own*
  `max_retries` column if set, else the factory-wide default (`2`) — and
  it's re-read fresh every reconcile tick (`launcher.go` comment: "so an
  operator's settings-UI edit takes effect without a factoryd restart").
  Raising the per-project override lifts the threshold retry_count is
  compared against, so already-retried issues stop qualifying for opus:
  ```bash
  curl -sS -X PATCH -H "Authorization: Bearer $FACTORY_API_TOKEN" -H "Content-Type: application/json" \
    "$API/v1/projects/3" -d '{"max_retries": "5"}'
  # note: value must be a JSON string ("5"), not a bare int — {"max_retries": 5} 400s
  ```
  Separate knob, don't confuse them: `max_escalations` governs the
  *unrelated* consecutive-silent-exit → `human` safety net
  (`deadworkers.go`/`stalecoding.go`) — raising `max_retries` doesn't touch
  that escalation path.
- **`queue-issue` labels on pods**: `kubectl get pods -l queue-issue=<id>` is
  the fast way to find a running worker for a specific issue without
  guessing job names.
