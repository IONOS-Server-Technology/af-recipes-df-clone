---
name: af-create-recipe
description: Bootstrap a new Application Factory recipe from an app name or upstream URL. Researches the app, drafts the five recipe files (metadata.yaml, docker-compose.yaml, .env.template, install.sh, health-check.sh), and self-checks the result against rfc/002-recipe-rules.md before handing the diff back to the developer for review and PR. TRIGGER when the user wants to "create a new af-recipe", "add an app to the catalogue", "bootstrap a recipe for <app>", "new application factory recipe", or references IF-548 / WP4. SKIP for: editing an existing recipe (just edit), Container Factory work (cf-* skills), or autonomous batch generation (out of scope for Phase 1).
---

# Bootstrap a new AF recipe

Phase 1 of WP4 (IF-548) — a developer-facing recipe authoring loop. The developer drives; the skill drafts, self-checks, and hands back a clean diff. The developer reviews, commits, and opens the PR manually.

## Operating mode

- Run from inside a clone of `af-recipes`. The CWD must be the repo root (where `recipes/` and `rfc/` live). If a Bash command in Phase 1 fails because those paths don't exist, stop and tell the developer to `cd` into the af-recipes clone before re-triggering.
- This skill **never** commits, pushes, or opens PRs on its own. It produces files and a handover blurb. The developer ships it.
- This skill **does not depend on `af-validate` or any external CLI**. The validation rules live in `rfc/002-recipe-rules.md` in this repo and are applied by the agent itself in Phase 4. If `af-validate` is also installed, the developer can run it as an independent cross-check after the handover — it implements the same rules from the same RFC.

## Phase 1 — Intake (silent if the trigger is complete)

Parse the trigger for: app slug, upstream URL (GitHub or Docker Hub), and any extra flags (`native`, a specific version pin, "no postgres", etc.). Then, in this order:

1. **CWD check.** If `recipes/` or `rfc/` are not visible from the current directory, stop and tell the developer to `cd` into the af-recipes clone before re-triggering.
2. **Conflict check.** Run `ls recipes/` and look for the slug. If it already exists, stop and ask whether the intent is an update (this skill is for *new* recipes only).
3. **Missing-info check.** If the trigger gave only a slug with no upstream, ask once for the source. If the trigger gave nothing recognizable, ask for the app name and a source.

If 1–3 all pass and nothing is missing, **do not ask the developer anything else** — proceed straight to Phase 2.

Defaults that do not need confirmation here:

- `recipe_type` defaults to `docker-compose`. Only switch to `native` later in Phase 3 (Plan) if Phase 2 research shows the app has no official Docker image.
- Do not ask for the JIRA ticket number here. That belongs in Phase 5.

The first real confirmation point with the developer is at the end of Phase 2 (research summary). That is where their input has actual value, because the agent has produced something that could be wrong. Phase 1 is bookkeeping.

## Phase 2 — Research

Goal: build enough understanding to write a sensible draft. Not exhaustive analysis.

- Read the upstream README and any `docker-compose.yml` they ship.
- **Record where that compose file came from** — this is not optional research, it goes into `metadata.yaml` in Phase 4 as `compose_file_url` / `compose_file_notes` (RFC-001 §4.7):
    - `compose_file_url` is the direct link to the *file* (raw/blob URL), not the docs page that embeds it. Prefer a tag- or SHA-pinned link over a `main`/`master` one.
    - `compose_file_notes` records the judgement calls: which variant was picked when upstream ships several (`withPostgres` vs `withMariaDB` …), whether the link is version-pinned or a rolling default-branch reference, and anything upstream leaves unpinned that we pin (e.g. an image tag floated via an env var).
    - If the project publishes no official compose file — including every `native` recipe — set `compose_file_url: null` and say why in the notes. `null` means "we looked and there is none", not "we didn't check".
- Read the Docker Hub page for the official image and pick a **pinned, current stable tag** — never `:latest`.
- Pick **2–3 existing recipes in `recipes/`** that are structurally similar and use them as templates. Heuristics:
    - Needs Postgres → `recipes/n8n/`, `recipes/paperless-ngx/`
    - Single-container web app → `recipes/uptime-kuma/`, `recipes/vaultwarden/`
    - Multi-service stack → `recipes/anytype-server/`, `recipes/immich/`
    - Native (no Docker) → `recipes/claude-code/`
- Summarize back to the developer in **5–8 bullet points**: what the app is, what services it needs, exposed ports, what parameters the customer must provide, the upstream compose reference (URL, or "none — <reason>"), the closest existing recipe, any caveats (privileged needs, GPU, weird volumes, license).
- Wait for the developer to confirm or correct the summary before generating.

## Phase 3 — Plan

Present a one-screen plan:

- File list (5 files for `docker-compose`; 3 for `native`)
- `metadata.yaml` skeleton: name, version (pinned), categories, ports, parameters list, resource floors, upstream compose source (`compose_file_url` / `compose_file_notes`)
- Which existing recipe is the structural template
- Open questions (e.g., "is `:8080` OK or does the user want a different default port?")

Wait for developer OK or adjustments before writing files.

## Phase 4 — Generate + Self-Check against RFC-002

Write the files into `recipes/<slug>/`. Then **read [`rfc/002-recipe-rules.md`](../../../rfc/002-recipe-rules.md)** and walk every rule against the new recipe (and, for cross-recipe rules, against the catalogue).

Output one line per rule, identified by its slug:

```
files-required-compose       ✓
metadata-valid-yaml          ✓
image-tag-pinned             ✗ ERROR — image 'redis:latest' on service 'redis'
bind-mount-under-opt         ⚠ WARN  — bind mount '/var/data' should be under /opt/<slug>/
```

For every ERROR-level finding:

1. Identify the rule (the slug is descriptive enough to know what's wrong without looking up the RFC) and the violation
2. Patch the offending file
3. Re-run only the affected check

Loop until **zero ERROR**-level findings remain. WARN findings are reported but don't block; the developer decides.

When checking cross-recipe rules (`no-duplicate-public-port`, `incompatibility-ref-valid`), scan `recipes/` for sibling metadata. Don't assume the new recipe is the only one in the catalogue.

Important: don't invent rules that aren't in RFC-002 and don't suppress findings from rules that are. If a rule seems wrong for a legitimate case, flag it to the developer — the fix belongs in RFC-002, not in a recipe workaround.

## Phase 5 — Handover

Once Phase 4 is clean, present:

1. **Diff summary:** run `git status` and `git diff --stat` against `recipes/<slug>/`
2. **Suggested branch name:** `feature/IF-<ticket>-<slug>` (ask the developer for the ticket if not given)
3. **Suggested commit message** (keep it terse, factual; one-line subject, optional body)
4. **`gh pr create` body** following the af-recipes PR conventions: link the JIRA ticket, list the rules that passed, mention any WARN-level findings the developer chose to accept

Tell the developer to review the diff, commit, push, and open the PR themselves. The skill stops here.

## What this skill does NOT do

- Autonomous PR creation, n8n trigger, self-healing CI loop — that's WP4 Phase 2 (out of scope, see [IF-548 comment from 2026-05-04](https://hosting-jira.1and1.org/browse/IF-548))
- PII stripping pipelines (also Phase 2)
- Updating existing recipes — separate skill `af-update-recipes` planned for v1.5; that's the maintenance sweep over RFC-002 changes
- Inventing app versions — always pin to a tag visible on Docker Hub or the upstream releases page
- Calling `af-validate` or any external linter — RFC-002 is the source of truth, applied by the agent itself

## Bash hook caveat

This developer's environment blocks Bash command chaining with `&&` or `;`. Make tool calls separately rather than chaining. Example: don't `mkdir -p X && touch Y` — make two calls. This is unrelated to the recipe content; it's a workflow constraint.

## References

- [`rfc/002-recipe-rules.md`](../../../rfc/002-recipe-rules.md) — the validation rules this skill enforces in Phase 4 (canonical)
- [`rfc/001-recipe-schema.md`](../../../rfc/001-recipe-schema.md) — formal schema spec, what each file is for
- `references/recipe-anatomy.md` — annotated walkthrough of `recipes/n8n/` as a learning template
- `recipes/n8n/` — canonical Postgres-backed example

## Out-of-band notes for the developer

- DPA with Anthropic for Claude API: not required for this workflow because the agent runs locally on the developer's laptop and only sees public upstream docs and the developer's own recipe drafts. Customer data never enters this loop.
- Few-shot corpus is the **22 existing recipes in this repo**, not Coolify. Coolify's `templates/compose/` is too noisy and inconsistent for the AF style.
