Title: Find compose file: {{name}}

Find the OFFICIAL `docker-compose.yaml` (or `.yml`) for "{{name}}" and
record it in `apps-gaps/{{slug}}.yaml`'s `upstream` section. This is
additive only — do not change any other field, do not re-research or
revise version_health/catalogue_fit/installability/summary.

## What "official" means

The project's own documentation or repository must be the source — not a
third-party template site, not a random fork, not an "awesome-selfhosted"
aggregator. Example of a good find, for reference (Immich):
docs.immich.app/install/docker-compose/ links to
github.com/immich-app/immich/releases/latest/download/docker-compose.yml —
a file the project itself publishes and updates.

## Where to look

1. The project's own docs site — search for "install", "self-host", or
   "docker-compose" in their documentation nav.
2. The GitHub (or other SCM) repo's README — installation sections often
   link or embed a compose file directly.
3. The repo itself — a `docker-compose.yaml`/`.yml` at the root, or under a
   `docker/`, `deploy/`, or `contrib/` directory.

## What to record

Add these two fields under `upstream:` in `apps-gaps/{{slug}}.yaml`:

```yaml
upstream:
  ...existing fields, unchanged...
  compose_file_url: <the URL, or null>
  compose_file_notes: <see below>
```

- **If found**: set `compose_file_url` to the direct file URL (prefer a
  GitHub release-asset link like Immich's example, or a raw link to the
  file in the repo, over a docs page that merely embeds/describes it).
  In `compose_file_notes`, state whether the link is version-pinned
  (e.g. a specific release tag or a `/releases/latest/download/...`
  redirect) or a rolling reference to a default branch (this matters for
  how the link gets watched for changes later) — and which variant you
  picked if the project ships more than one (GPU vs CPU, dev vs prod,
  sqlite vs postgres, etc.) and why.
- **If the project only ships a community-maintained compose file, no
  official one**: set `compose_file_url: null` and say so in
  `compose_file_notes` — do not adopt the community one as if it were
  official.
- **If nothing usable exists at all** (e.g. the app only documents a bare
  `docker run` command, or `recipe_type_guess` is `native` and there's no
  compose file by definition): set `compose_file_url: null` and say why in
  `compose_file_notes`.

## Before committing

Run `python3 bin/validate-apps-gaps {{slug}}` (see `CLAUDE.md` for the
pyyaml/jsonschema bootstrap if needed) and confirm zero errors.

Commit only `apps-gaps/{{slug}}.yaml`. No recipe files, no other files, no
other field changes.

## This is enforced, not just requested

`CLAUDE.md` requires the reviewer to independently re-run
`bin/validate-apps-gaps {{slug}}` against this file before approving.
`.github/workflows/validate-apps-gaps.yaml` also checks it on GitHub after
your commit lands on `main`, scoped to the file(s) you touched.
