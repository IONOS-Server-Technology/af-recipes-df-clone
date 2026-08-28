# Getting `build_now` apps into the MVP catalogue

Scope: the 221 apps marked `recommendation: build_now` in
`apps-gaps-full-export.csv` — mechanically installable today, no platform
gap, nothing blocking. Goal here is not more research, it's **throughput**:
turn each one into a real `af-recipes` PR.

## The constraint this has to work around

`af-create-recipe` (the skill that does this today, in
`af-recipes/.claude/skills/af-create-recipe/`) is built as an **interactive
developer loop** — it stops for a human at three points (post-intake,
post-research, post-plan) and never commits, pushes, or opens a PR itself.
That's correct for one-off recipes, but doesn't scale to running it 221
times by hand. Autonomous batch generation is explicitly listed as
out-of-scope in the skill's own doc (WP4 Phase 2, not built).

So the design goal for this pipeline is **not** "make it fully autonomous."
It's: collapse each interactive checkpoint into one non-interactive
dark-factory run that produces a draft, then keep exactly the same kind of
human review gate the skill already has today — just once per app instead of
three times per app. This mirrors what the existing 997-app gap-analysis
pipeline already did (one dark-factory issue per app, analysis-only, no PR) —
same shape, just producing real files this time instead of a report.

## Task breakdown

### Task 1 — metadata.yaml, seeded from the gap-research file

Source: `af-recipes-clone/apps-gaps/<slug>.yaml` (999 files, schema-validated
against `apps-gaps/schema.json`) — **not** the flattened
`apps-gaps-full-export.csv`. The per-app file is real research, not a
spreadsheet row: `upstream.url`/`repo_url`/`license`/`docker_image`,
`upstream.compose_file_url`/`compose_file_notes` (the actual official
compose reference, when one exists), `version_health` (cadence, EOL
status), `catalogue_fit` (categories, overlap with existing recipes), and a
narrative `summary` that often already names the closest structural
template (e.g. actual-budget's file says outright "matching the
uptime-kuma single-container pattern").

This task's job: turn that into `metadata.yaml` — `id`, `display_name`,
`description`, `categories`, `app_version`, `recipe_type`, `ports[]`,
`parameters[]`, resource floors. The research file gives the inputs but
doesn't decide ports or the exact parameter list — that's still a real
decision this task makes, informed by `compose_file_url` when there is one.

**Versions — do not pin by default (IF-1501).** `IF-1501` ("Selected",
resyncing the existing 22 recipes) sets the policy going forward: **adopt
upstream's own versioning choice as-is**, including a floating tag, rather
than resolving it to a pinned number. If upstream floats (n8n's
`${N8N_VERSION:-stable}`), we float too. `test-recipes-live` is the safety
net, not a pin. This directly serves "scale out to more apps" — it removes
an entire research/decision step (finding and re-verifying a current pinned
tag) from every one of the ~216 remaining `build_now` apps.

This does **not** require an RFC-002 change — checked directly:
`image-tag-pinned` (ERROR) only fails on a literal `:latest` or a missing
tag; `app-version-pinned` (ERROR) only fails on the literal string
`"latest"`. A rolling alias like `${N8N_VERSION:-stable}` already passes
both today. What actually needs to change is `af-create-recipe`'s own Phase
2 instruction — "pick a pinned, current stable tag — never `:latest`" is
stricter than what's enforced, and it's the thing driving today's
pin-everything default. Update that instruction (or this task's version of
it) to: *match `compose_file_url`'s own choice; only pick a fresh pin
yourself when no official compose reference exists to copy from.*

Output: `recipes/<slug>/metadata.yaml`, `recipe_version: 0.1.0`, nothing
else written yet.

### Task 2 — docker-compose.yaml + .env.template + install.sh + health-check.sh

Consumes Task 1's `metadata.yaml` as a fixed input — ports and parameters
are already decided, so this task implements them rather than co-deciding
them. That's a genuine sequential dependency (not a bundle-to-avoid-
inconsistency): `docker-compose.yaml`'s exposed service must match
`metadata.ports[]`, `.env.template` placeholders must match
`parameters[].name`, `install.sh` must match the compose structure. Mirrors
`af-create-recipe` Phase 4 (Generate + self-check against
`rfc/002-recipe-rules.md`, looping until zero ERRORs), collapsed into one
non-interactive pass.

Image version follows Task 1's decision (upstream's own pin-or-float
choice, per IF-1501) — this task doesn't re-litigate it.

**Self-check stays inside this task**, not a separate one — it's a tight
generate → check → patch → re-check loop against the files just written,
same as `af-create-recipe` Phase 4 today. Splitting it out would just add a
round-trip for a check that only makes sense immediately after generation.

**Commits and pushes on its own, same as Task 1 — no "hold the push"
step.** Each dark-factory job runs in a fresh container; nothing survives
between separate issues unless it's actually pushed, and a coding job that
finishes without a push reads to the dispatcher as a silent exit or an
unreviewable diff (confirmed the hard way on Task 1: "draft only, don't
push" produced a multi-attempt retry storm with nothing ever landing).
There's also no GitHub PR concept anywhere in dark-factory — completion
means a verified `git push` straight to `origin/main`, done by the reviewer
worker's own shell. `enabled: false` (already set by Task 1) keeps this
non-customer-visible regardless of when it merges, so there's no reason to
delay the push.

Output: `docker-compose.yaml`, `.env.template`, `install.sh`,
`health-check.sh` added under `recipes/<slug>/`, committed and pushed
independently of Task 3 (disjoint files — no shared commit needed, no file
conflict). RFC-002 self-check output (all ✓, WARNs noted) reported on the
issue.

### Task 3 — Logo

Already a finished, tested tool: **`af-recipe-logo`** skill (lives in
`if-claude-marketplace/plugins/image-factory/skills/af-recipe-logo/`, built
for IF-1416, now Resolved; vendored into `af-recipes-clone/.claude/skills/`
for dark-factory to use, with `find_source.py`'s GitHub lookups switched
from the `gh` CLI to plain unauthenticated `api.github.com` calls since the
worker has neither `gh` nor a token). Not something to build — it runs
end-to-end in one task.

Pipeline: `find_source.py <id>` walks a fixed waterfall (website favicon →
upstream repo SVG → dashboardicons SVG → upstream PNG ≥480px →
dashboardicons PNG) → `normalize.py` reframes to a square viewBox / 90%
safe area / transparent background, with `--tile` producing a light+dark
preview → `verify.py` checks it against the 10 `af-validate` logo rules
(square viewbox, safe area, centered, transparent bg, no animation, no
embedded script/XXE, contrast, wordmark detection) → `apply.py` writes
`logo.svg` and the `logo_*` metadata fields, commits, and pushes — same
push-to-`main` model as every other task (no PR, dark-factory has none).

**Originally split into 3a (find+normalize+verify, research-only) and 3b
(apply, gated on a human accepting the 3a preview) — merged back into one
task.** The split existed solely to enforce a per-app human review of the
logo before it landed; that gate turned out to not actually happen in
practice (nobody was looking at every tile), and separately isn't the real
safety net anyway — every recipe stays `enabled: false` until a human
flips it, which is where the actual customer-facing risk is gated. With no
per-logo human step, there's no reason to split what the skill treats as
one linear pipeline (steps 1-4 in its own `SKILL.md`) across two issues
with a manual URL hand-off between them.

**Before merging, this cost real data: `verify.py` missing something a
human tile-look caught, twice**, in the one batch that still went through
per-app review (10 apps): `ghost`'s chosen mark was illegible (an empty
ring on light, nothing visible on dark — no ghost silhouette at all) and
`nextcloud`'s first candidate was an opaque black background plate mistaken
for "clean transparent-bg black ink." `verify.py` reported both as clean.
That's now written directly into the merged task's instructions (step 6):
actually read the rendered tile PNG, don't trust a clean `verify.py` run
alone. It's a weaker check than a dedicated human gate was, but a real one
— not the nothing the 3a/3b split was actually getting in practice.

**Requires `recipe_version` to already exist** in `recipes/<slug>/metadata.yaml`
(`apply.py`'s own requirement, confirmed by reading it directly) — so this
task still needs Task 1 to have landed first, same dependency the old 3b
had. It does NOT need Task 2's files, and touches disjoint ones (`logo.svg`
+ `metadata.yaml`'s `logo_*`/`recipe_version` vs. Task 2's
compose/env/install/healthcheck) — commits and pushes independently of
Task 2, same as before.

### Task 4 — Independent validation (`af-validate`)

Deliberately kept separate from Task 2's self-check: `af-create-recipe`
explicitly does **not** call `af-validate` — its self-check is the agent
re-implementing RFC-002 itself. Running the real `af-validate recipe
recipes/<slug>/` CLI afterward is a genuinely independent second opinion
(separate implementation, same spec). Worth keeping visible as its own step
— the IF-1416 review caught a stale `catalogue.json` and a CI flag mismatch
that only surfaced when something *other* than the authoring skill checked
the output. Cheap and fast; no reason to skip it even though it's small.

### Task 5 — Test

Two tiers already exist in CI, both callable via `workflow_dispatch` with a
comma-separated recipe list — **no new test infrastructure needed**:

- **Phase 1 — `test-recipes-docker.yaml`** (~2-5 min): brings the recipe up
  via `docker compose` on the GitHub runner, no VM. Fast first gate.
- **Phase 2 — `test-recipes-live.yaml`** (~10-15 min): provisions a real
  ephemeral CoreVPS VM via the IONOS Cloud API and runs the actual
  cloud-init → `af-cloud-init` → `/bootstrap` → `install.sh` flow against an
  ephemeral `af-api`. This is the real proof, not just "compose file
  parses" — and specifically the thing that makes an unpinned/floating tag
  (IF-1501) safe to ship: it's the safety net upstream's own version churn
  is being trusted against.

A dark-factory run for this task = `gh workflow run
test-recipes-docker.yaml -f recipes=<slug>` against whatever is currently on
`main` for that recipe (and later, live), then poll and report. This is
pure validation — no file changes, so no push. Use `queue transition <id>
done -f` (the documented override for "genuinely no code to verify") once
the workflow run comes back clean; don't let the reviewer stall waiting for
a git diff that will never exist. **Known noise to filter, per the IF-1416
review:** live-VM tests can fail on CI-account resource quota (`VDC-5-1005:
personal limit of 300 CPUs exhausted`) — unrelated to the recipe. A
dark-factory test run needs to distinguish that from a real failure before
reporting red, or the pilot will look worse than it is.

## Dependency graph

```
Task 1 (metadata.yaml, from apps-gaps/<slug>.yaml) ──┬──> Task 2 (compose+install+env+healthcheck) ─┐
                                                      │                                              │
                                                      └──> Task 3 (logo: find+normalize+verify+apply) ┼──> Task 4 (af-validate)        ─┐
                                                                                                       └──> Task 5 Phase 1 (docker test) ─┼─> human flips enabled:true → Task 5 Phase 2 (live VM)
                                                                                                                                          ─┘
```

Task 2 and Task 3 both need only Task 1's `metadata.yaml`, touch disjoint
files, and each commits and pushes to `main` on its own — no shared commit
between them, no PR (dark-factory has none). Task 4 and Task 5-Phase-1 use
`requires: [task2_issue_id, task3_issue_id]` on issue creation so
dark-factory itself blocks them until both have landed. Task 5-Phase-2
(expensive) only runs once 4 and 5-Phase-1 are both clean.

**Human review gate: once — flipping `enabled: true`.** All of Tasks 1-3
land on `main` independently as they complete (safe: `enabled: false` keeps
every intermediate state non-customer-visible), so there's no combined diff
to hold back for. The one deliberate human checkpoint is reviewing and
merging the small `enabled: true` flip once Task 4 and Task 5-Phase-1 are
both clean — a much smaller, cleaner diff than the "combined diff across 3
tasks" a PR-based model would have produced, and dark-factory has no PR
concept to open one with anyway.

## Pilot set: 5 apps

Picked for structural diversity (single-container vs. multi-service) and
product-cluster spread, all `recommendation: build_now`, none overlapping
an already-enabled recipe:

| Slug | Cluster | Structural pattern | Upstream image |
|---|---|---|---|
| `actual-budget` | Finance | single container | `actualbudget/actual-server` |
| `alist` | Storage | single container | `xhofe/alist` |
| `code-server` | Notebook/dev env | single container | `codercom/code-server` |
| `metabase` | Finance-adjacent (BI) | single container, official image | `metabase/metabase` |
| `joomla` | CMS | multi-service (app + MySQL) | `joomla:6.1.2-php8.4-apache` |

4 of 5 are single-container — cheapest, lowest-risk for proving the pattern.
`joomla` deliberately exercises the DB-pairing structural template (like
`n8n`/`paperless-ngx`) to test whether Task 2 handles that class too, not
just the trivial case.

## Suggested sequencing for the pilot

1. Task 1 (metadata.yaml, from `apps-gaps/<slug>.yaml`) + Task 3a (logo
   find+normalize+verify) for all 5, in parallel — both have zero
   dependency on anything else, so both start immediately.
2. Human looks at the 5 tile previews (Task 3a), accepts or redirects each.
   Independently, spot-check Task 1's port/parameter decisions and version
   policy (float-vs-pin per IF-1501) against each `compose_file_url`.
3. Task 2 (compose+install+env+healthcheck) and Task 3b (apply logo) for
   all 5, in parallel — each commits and pushes independently once its own
   prerequisites (Task 1, plus Task 3a for 3b) are accepted.
4. Task 4 (af-validate) + Task 5 Phase 1 (docker test), dispatched with
   `requires` pointing at both Task 2's and Task 3b's issue ids per app, so
   dark-factory holds them until both have actually landed on `main`.
5. Human reviews and merges the `enabled: true` flip for each app that's
   clean — the one deliberate gate.
6. Task 5 Phase 2 (live VM) runs once `enabled: true` is merged.
7. Retro before scaling: which of the 5 needed a human correction, and at
   which task? That answers whether the task boundaries above are right
   before running this against the other 216 `build_now` apps.

## Open questions to settle before running this for real

- Where does a *generation* task write its output — a branch per app
  directly in `af-recipes`, or a scratch location a human copies in? (Unlike
  the analysis-only gap pipeline, this one produces real repo files.)
- Who is the reviewer for the pilot's single human gate (step 5), and do
  they see Task 3a's tile previews and Task 1's port/version decisions
  separately (step 2) or only once at the end?
- `af-create-recipe`'s Phase 2 picks a structural template by matching
  against 2-3 similar *existing* recipes — for a batch of 5 running at once,
  should later apps in the batch also consider the *other pilot apps'*
  freshly-generated recipes as templates, or only the pre-existing 24? (Only
  the pre-existing 24 is safer for a first pilot — avoids compounding an
  early mistake across the batch.)
- Does IF-1501's float-vs-pin policy get written down anywhere Task 1 can
  point to as its instruction (an updated `af-create-recipe` Phase 2, or a
  standalone note in RFC-002/RFC-001), or does this pipeline just carry its
  own copy of the rule until IF-1501 lands for the existing 22 and the
  skill doc gets updated to match?

## Backlog — pipeline gaps, not yet designed or built

Things the pilot batch surfaced that aren't covered by Tasks 1-5 as they
stand today. None of these have a template yet; capturing them here so they
don't get lost before the next design pass.

- **A holistic sanity/completeness pass, after logo (task 3) and before
  af-validate.** Tasks 1-3 each check their own narrow slice (metadata
  fields, RFC-002 on the compose files, logo spec) — nothing currently
  looks at the *whole* recipe together and asks "does this actually hang
  together as an MVP-installable app, and did any earlier task miss
  something the others couldn't have caught?" (e.g. a parameter task 1
  declared that task 2 never actually wired into `.env.template`, or a port
  task 2 opened that task 1's `ports[]` doesn't list). Would sit right
  after task 3, before task 4 — everything else in the pipeline currently
  jumps straight from "the pieces exist" to "run the mechanical checks"
  with nothing in between that reads the recipe as a whole.
- **Resource sizing (RAM/disk) is currently a guess, not a measurement.**
  Task 1 step 6 sets `app_min_ram_mb`/`app_min_disk_mb` by copying the
  chosen template recipe's own values, "adjusted only if upstream's docs
  state a materially different requirement" — that's a copy-and-hope, not
  anything measured against the actual app. Needs a real step: either run
  the container and observe actual usage (most trustworthy, costs a
  container run per app), or a more rigorous docs/release-notes read than
  Task 1 currently does. Where this sits in the sequence depends on the
  answer — if it's a real container run, it likely wants task 2's compose
  file to already exist; if it's research-only, it could run in parallel
  with task 1/3 like the rest of the independent tasks.
- **License/legal review is currently shallow.** `apps-gaps/<slug>.yaml`'s
  `upstream.license` is whatever the original ~1000-app gap-analysis pass
  recorded (an SPDX-style read, not a legal review), and Task 1 just
  carries that value forward as-is. Needs an actual check before an app
  ships: AGPL/SSPL-style copyleft implications for hosting as a paid
  service, "open-core" apps where the self-hosted edition's license differs
  from what the marketing page implies, trademark use beyond what the logo
  task already covers (`trademark-nominative-fair-use` there is about the
  *mark*, not the *product* being resold as a hosted offering). Not yet
  clear whether this is a per-app dark-factory task at all, or something
  that stays human-only.
- ~~`actual-budget`/`metabase`'s `health-check.sh` hard-required
  `$SERVERIP` with no fallback~~ — **fixed** (`7b1d7dc8`), switched to the
  dual-mode pattern. Same bug recurred once more on `nextcloud` in batch 2
  (also fixed, same commit) because `docs/health-check-spec.md`'s own
  "Retry Pattern" example teaches the broken pattern — `MVP_TASK2_COMPOSE_TEMPLATE.md`
  step 3 now explicitly warns against copying that doc's example verbatim.
- **WUD labels (`wud.trigger.include`/`wud.compose.file`) — 4 of 5 pilot
  recipes don't have them**, only `metabase` does. Not an RFC-002 rule, so
  not a hard failure, but a drift from the existing catalogue's pattern.
  Undecided whether it's worth enforcing given WUD's `docker_auto_inject`
  is currently disabled (IF-1465) — may be dead weight in the *old*
  recipes rather than a real gap in the new ones.
- ~~238 of ~240 `health-check.sh` scripts derived the Compose project name
  from the script's own directory (`basename(dirname(BASH_SOURCE))`) and
  filtered `docker ps` by that project label~~ — **fixed, batch pass
  complete (2026-08-26).** `test-recipes-docker.yaml` runs Compose with
  `--project-name "afpre-<recipe-id>"`, not the bare recipe id, so this
  filter matched zero containers and the health check spun for the full
  300s timeout every time — even when the app itself was perfectly
  healthy. Found via the `buzz` PR's actual CI run
  (github.com/IONOS-Server-Technology/af-recipes/pull/96), confirmed by
  reproducing locally and by reading `test-recipes-docker.yaml` line 431.
  Passed every static check (`af-validate` has no rule for it, and Task
  4's own audits repeatedly praised this exact pattern as "correctly
  implements the dual-mode pattern" because they only read the shape,
  never ran it against a differently-named Compose project). Fixed by
  filtering on container name instead, anchored to a project/service
  boundary — `--filter "name=(^|-)<slug>-"`, **not** a bare substring: a
  bare substring turned out to be a second, real bug (`kan`/`kanboard`,
  `kan`/`kaneo`, `ghost`/`ghostfolio` all collide, and
  `test-recipes-combinations.yaml` deploys multiple recipes on one host,
  so an unanchored filter could silently match another app's containers).
  Verified with live end-to-end runs (stack brought up under a
  deliberately mismatched project name) on 3 structurally different
  recipes, not just a syntax check. All 239 affected `health-check.sh`
  files fixed in one batch; `buzz` fixed separately in its own PR.
  `MVP_TASK2_COMPOSE_TEMPLATE.md` and `MVP_TASK4_SANITY_CHECK.md` both
  updated so future recipes don't reintroduce either version of this bug.
