# Draft 1 of 2

## Summary
AF - Add upstream docker-compose source metadata to recipes

## Description
Every recipe's `docker-compose.yaml` is a hand-adapted derivative of some
upstream reference (an official docs page, a GitHub release asset, a raw
file in the project's repo) — but we don't record *where that upstream
source is* anywhere. There's no way today to look at a recipe and know
what to diff it against, or to programmatically find "which recipes have
an official upstream compose file at all."

Example — n8n: the official reference is
`github.com/n8n-io/n8n-hosting/blob/main/docker-compose/withPostgres/docker-compose.yml`,
which pins `postgres:16` and floats the n8n image itself via
`N8N_VERSION` (defaulting to `stable` in `.env`, i.e. not version-pinned
at all). Right now nothing records that this is n8n's source, or that
it's a rolling reference — `recipes/n8n/metadata.yaml` has no field for
it.

Add two fields to carry exactly that:
- `compose_file_url`: the direct URL to the file (nullable — `null` when
  no official one exists).
- `compose_file_notes`: free text — which variant was picked if the
  project ships several, whether the reference is version-pinned or a
  rolling default-branch link, or why no official file exists.

## Acceptance Criteria
- `compose_file_url` (string, nullable) and `compose_file_notes` (string,
  nullable) added to the recipe metadata schema. Both optional/not
  required — this must not fail CI for existing recipes that don't have
  them yet.
- **Cross-repo dependency, sequence accordingly**: the actual enforced
  schema lives in `af-api`'s `src/af_api/core/schema/metadata.schema.json`
  (`additionalProperties: false`), applied via `jsonschema.validate()` in
  `recipe_validator.py` and run in CI as the `af-validate-rfc002` job in
  `af-recipes`. The two fields must be added there first (and released)
  before any `af-recipes` metadata.yaml can carry them without failing
  CI's schema check.
- `rfc/001-recipe-schema.md`'s field table updated to document both
  fields.
- `.claude/skills/af-create-recipe/SKILL.md` Phase 2 updated so every
  *future* recipe records this automatically as part of research, not just
  the one-time backfill in the follow-up card.
- Out of scope for this card: populating the fields for the 22 existing
  docker-compose recipes (native recipes — claude-code, gemini-cli — have
  no compose file by definition and should record `null` with a note
  saying so). That's the second card.
