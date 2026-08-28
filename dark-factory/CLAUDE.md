# Operating dark-factory — context for Claude Code sessions started here

This directory (`~/claude/dark-factory/`) is the **operator's** working
directory for driving a running dark-factory instance — not the factory's
own source code. That lives in a separate git repo:
`~/gitea/dark-factory-go-ts` (its own `CLAUDE.md` documents the factory's
architecture, Makefile targets, and mandatory rules for changes *to* the
factory itself — read that one if you're modifying dark-factory's code, not
this one).

This directory exists so operator-side planning docs, infra notes, and
per-managed-project context don't live inside the factory's own git history
(they're not code changes, they're session-to-session continuity for
whoever — human or Claude — is running the thing).

## Current live infrastructure (update this section when it changes)

- **VPS**: `ssh dark-factory` → `87.106.38.71`, root, Debian 13, 16 vCPU /
  31GB RAM. Runs k3s (single node, hostname `dark-factory`).
- **Why a VPS at all, not local k3s or a laptop VM**: `git.ionos.org` (the
  factory's own repo host) is on an RFC1918 address unreachable from
  outside the office network/VPN. A local QEMU/KVM VM was tried first and
  hit an unresolved networking dead end on corporate WiFi (suspected
  anti-tethering detection — never proven, abandoned rather than worked
  around). A plain public VPS sidesteps this entirely, at the cost of the
  VPS itself also being unable to reach `git.ionos.org` — irrelevant in
  practice since none of the *managed* projects are hosted there.
- **kubectl**: laptop's `~/.kube/config` context is `dark-factory-vps`,
  server `https://87.106.38.71:6443`.
  `KUBECTL_CONTEXT_OVERRIDE=yes` is required for `make factory-*` targets
  in dark-factory-go-ts, since the Makefile only auto-recognizes the
  `k3s-colima` context name as "known safe."
- **Registry tunnel** (needed before building/pushing any image from the
  laptop): `ssh -fN -L 5000:localhost:5000 dark-factory` — laptop's own
  local `buildkitd` (already running, leftover from earlier setup) builds
  images; this tunnel is how they reach the VPS's in-cluster registry.
- **factoryd UI/API**: `http://87.106.38.71:30080/`. Bearer token lives in
  the `dark-factory` namespace's `factory-secret` Secret, key
  `FACTORY_API_TOKEN` — see rest-api-usage.md for how to fetch it.
- See **[rest-api-usage.md](rest-api-usage.md)** for the actual curl
  patterns (issue create/transition, job logs, the `/v1/*` vs. web-form
  endpoint split, secret-fetching commands) — that's the reference for
  *how* to drive factoryd from a shell, this file is *what's currently
  running*.

## An earlier VPS existed and is gone

An earlier, smaller VPS (`31.70.87.245`, 2 vCPU/4GB) ran a first test
project (`fibonacci-rest-api`) and was deliberately replaced with the
current, more powerful box. It's unreachable now (decommissioned) — nothing
of value was lost doing this: all code lives on GitHub independent of any
VPS, and the queue/job history that only existed in that VPS's Postgres was
explicitly not something the operator cared to keep.

## Managed projects (dark-factory `project` rows on the current VPS)

Each project is its own git repo dark-factory clones/pushes to — not
related to `~/gitea/dark-factory-go-ts` at all. Their own git checkouts on
the laptop typically live under `~/github/<org>/<repo>/`, separate again
from this directory.

- **`recipe-catalogue`** (project id 2) — a recipe-catalogue REST API
  (FastAPI + SQLite + Alembic), the current active test project for
  exercising the pipeline on richer, evolving-schema work. Planning doc:
  **[recipes-catalogue/PLAN.md](recipes-catalogue/PLAN.md)**. Repo's own
  `CLAUDE.md` (worker-facing conventions) lives in its checkout at
  `~/github/hteichmann-strato/recipe-catalogue/CLAUDE.md`, not here.

Add a new `<project-name>/PLAN.md` here (mirroring `recipes-catalogue/`'s
shape: why it exists, domain/schema decisions and why, deployment shape,
issue-sequencing plan, review cadence) for each new project the factory
starts managing.

## Working style established so far (carries across sessions)

- The operator drives long-running or consequential remote commands
  themselves (provisioning scripts, `make factory-up-local`, anything that
  takes real wall-clock time or touches production-ish state) — Claude
  handles diagnostics, staging (`scp`/`rsync`), read-only checks, and
  drafting. When in doubt on a given host, ask rather than assume.
- Issues get drafted and shown before submitting, not submitted blind,
  unless explicitly told to just submit.
- Cross-issue architectural drift is a known, real risk in this pipeline —
  no per-issue reviewer sees the whole repo, only its own diff. Mitigate
  with (a) a project-specific `CLAUDE.md` with concrete, checkable rules,
  not vague "write good code" instructions, and (b) a periodic holistic
  `/review` pass — a committed cadence, not a one-off audit. See
  `recipes-catalogue/PLAN.md`'s "Review cadence" section for the specifics
  agreed for that project.
