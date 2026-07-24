# RFC-002: Recipe Validation Rules

**Status:** Draft
**Author:** Florian Sauer (incorporating Oliver Knabe's spec-driven proposal from IF-548 comment, 2026-03-20)
**Date:** 2026-05-04
**Story:** IF-548 — WP4: AI-Assisted Recipe Authoring
**Related:** [RFC-001 — Recipe Schema Specification](001-recipe-schema.md)

## 1. Purpose

RFC-001 defines **what** a recipe is — directory structure, file roles, schema fields. This RFC defines **what makes a recipe acceptable** — the concrete, machine-checkable rules a recipe must satisfy before merging.

It is the single source of truth for:

- Recipe authors (human or AI agent) — generate against these rules
- The `af-create-recipe` Claude Code skill — applies these rules as a self-check before handoff
- The `af-validate` CLI in [af-core](https://github.com/IONOS-Server-Technology/af-core) — enforces these rules in CI
- Future maintenance sweeps — when a rule changes here, every existing recipe is re-checked against the new version

If a rule cannot be expressed concretely enough to be machine-checked, it does not belong in this RFC — it belongs in style notes.

## 2. Rule format

Each rule has:

- **ID** — a stable, descriptive slug (`no-public-db-port`, `image-tag-pinned`, …). Stable; never reused. Slugs are chosen to read like assertions, so a finding line in agent output or CI log is intelligible without looking up this RFC.
- **Level** — `ERROR` (blocks merge) or `WARN` (advisory).
- **What** — the rule, one sentence.
- **How to check** — concrete, deterministic procedure to evaluate the rule against a recipe.
- **Why** — the reason. Without this, the rule rots.

## 3. Per-recipe rules

These rules apply to a single `recipes/<slug>/` directory.

### 3.1 Files present

#### `files-required-compose`

- **Level:** ERROR
- **What:** A `docker-compose` recipe directory must contain `metadata.yaml`, `docker-compose.yaml`, `.env.template`, `install.sh`, `health-check.sh`.
- **How to check:** Read `metadata.yaml`, take `recipe_type` (default `docker-compose`). If `docker-compose`, verify all five files exist in the directory.
- **Why:** Each file has a distinct role at compose-time, install-time, or test-time. Missing any file makes the recipe non-deployable or non-testable.

#### `files-required-native`

- **Level:** ERROR
- **What:** A `native` recipe directory must contain `metadata.yaml`, `install.sh`, `health-check.sh`.
- **How to check:** As `files-required-compose` but for `recipe_type: native`. Compose and `.env.template` are not expected.
- **Why:** Native recipes do not run via Compose; they install directly on the OS via `install.sh`.

#### `scripts-executable`

- **Level:** WARN
- **What:** `install.sh` and `health-check.sh` must have the executable bit set.
- **How to check:** `test -x install.sh` and `test -x health-check.sh`.
- **Why:** Cloud-init invokes `install.sh` directly; non-executable scripts fail with permission denied.

### 3.2 metadata.yaml

#### `metadata-valid-yaml`

- **Level:** ERROR
- **What:** `metadata.yaml` must parse as YAML.
- **How to check:** `yaml.safe_load`. If it raises, fail.
- **Why:** Everything downstream assumes a parseable document.

#### `metadata-schema-valid`

- **Level:** ERROR
- **What:** The parsed metadata must satisfy [`metadata.schema.json`](https://github.com/IONOS-Server-Technology/af-core/blob/main/af_core/schema/metadata.schema.json).
- **How to check:** `jsonschema.validate(metadata, schema)`.
- **Why:** The AF API loads recipes against this schema at startup; a recipe that fails the schema crashes the API.

#### `id-matches-dir`

- **Level:** ERROR
- **What:** `metadata.id` must equal the recipe directory name.
- **How to check:** String comparison.
- **Why:** The directory name is the slug used everywhere (URLs, `incompatible_with_apps`, install paths). Divergence breaks lookups.

#### `app-version-pinned`

- **Level:** ERROR
- **What:** `metadata.app_version` must not be `latest` (case-insensitive).
- **How to check:** `str(app_version).lower() != "latest"`.
- **Why:** Customer machines need reproducible installs; rollbacks are impossible if `latest` shifts.

#### `recipe-version-semver`

- **Level:** ERROR
- **What:** `metadata.recipe_version` matches `^\d+\.\d+\.\d+$`.
- **How to check:** Regex.
- **Why:** Allows mechanical bumping when this recipe (not the upstream app) changes.

#### `short-description-required`

- **Level:** ERROR
- **What:** `metadata.short_description` must be present, be a language map (`dict[str, str]`), and contain an `en` key.
- **How to check:** Check presence and type; verify `"en"` key exists.
- **Why:** The customer-facing UI requires an English short description for every app; the `en` key is the fallback for all locales.

#### `short-description-max-length`

- **Level:** ERROR
- **What:** Each value in `metadata.short_description` must be ≤ 160 characters.
- **How to check:** For each key-value pair: `len(value) <= 160`.
- **Why:** UI display constraint — the control panel app card has a fixed character limit.

### 3.3 Logo

These rules enforce RFC-001 §4.6 — every customer-visible recipe has a logo, and the declared logo metadata is consistent with the file on disk.

#### `logo-required-when-enabled`

- **Level:** ERROR
- **What:** When `metadata.enabled: true`, all of `logo_url`, `logo_sha256`, `logo_license` must be present.
- **How to check:** If `enabled` is truthy, check each field is a non-empty string.
- **Why:** A customer-visible recipe without a logo renders as a blank card in the catalogue UI. Disabled recipes are exempt because they don't appear in the catalogue.

#### `logo-url-canonical`

- **Level:** ERROR
- **What:** `logo_url`, when present, matches `^https://appfactory\.s3\.eu-central-3\.ionoscloud\.com/recipes/<id>/<recipe_version>/logo\.svg$`, where `<id>` equals `metadata.id` and `<recipe_version>` equals `metadata.recipe_version`. SVG is the only supported extension.
- **How to check:** Regex match the URL; assert path components equal the recipe's own id and version.
- **Why:** Logos are served from one bucket on a versioned path; off-bucket URLs bypass our integrity model and break the sync workflow. Mismatched id/version components mean a copy-paste error that would point consumers at the wrong logo.

#### `logo-file-exists`

- **Level:** ERROR
- **What:** When `logo_url` is declared, the file `recipes/<id>/logo.svg` exists in the repo.
- **How to check:** Check that `recipes/<id>/logo.svg` exists.
- **Why:** Git is the source of truth (RFC-001 §4.6). A `logo_url` referencing a file that doesn't exist in the repo cannot be uploaded by CI and breaks the consumer.

#### `logo-sha256-matches`

- **Level:** ERROR
- **What:** When `logo_url` is declared, `logo_sha256` is a 64-char lowercase hex digest **and** equals the SHA-256 of the on-disk logo file.
- **How to check:** Validate the hex shape; compute `sha256(logo_file.read_bytes())`; compare.
- **Why:** Tamper-evidence. Without the hash check, a logo file could be edited in git (or replaced in S3) without anyone noticing — this rule pins the metadata to the exact bytes shipped.

### 3.4 Parameters

#### `param-name-upper-snake`

- **Level:** ERROR
- **What:** Each `metadata.parameters[].name` matches `^[A-Z][A-Z0-9_]*$`.
- **How to check:** Regex per parameter.
- **Why:** Convention used in `.env` files and shell scripts; mixed case breaks shell expansion.

#### `placeholder-has-param`

- **Level:** ERROR
- **What:** Every `{{KEY}}` token in `.env.template` corresponds to a `metadata.parameters[].name`.
- **How to check:** Regex `\{\{(\w+)\}\}` over the template, set-difference against parameter names.
- **Why:** Render-time substitution would leave the placeholder literal in the env file, breaking the container.

#### `param-referenced`

- **Level:** WARN
- **What:** Every `metadata.parameters[].name` appears either in `.env.template` as `{{KEY}}` or in a place the AF API can resolve (compose `${KEY}`, install.sh).
- **How to check:** For each param name, grep the recipe directory; if no hit, warn.
- **Why:** Unreferenced parameters are usually typos or dead code; they confuse the customer-facing UI.

#### `auto-generate-password-only`

- **Level:** ERROR
- **What:** `auto_generate: true` is only allowed where `type: password`.
- **How to check:** For each parameter, if `auto_generate` is true and `type != password`, fail.
- **Why:** The AF API generates a 32-char `[a-zA-Z0-9]` value; only meaningful for secret-type fields.

#### `param-value-charset`

- **Level:** ERROR
- **What:** Every parameter `default` value matches the charset allowed for its declared `type`:
  - `domain`: hostname pattern `^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$`
  - `boolean`: exactly `true` or `false`
  - `string` / `password` / any other type: no newline characters (`\n`, `\r`) and no unquoted
    shell metacharacters (`` ` ``, `$`, `(`, `)`, `;`, `|`, `&`, `<`, `>`, `\`)
- **How to check:** For each parameter with a `default`, validate the value against the pattern
  for its type.
- **Why:** af-recipes does not escape or quote parameter values when rendering — the af-core
  renderer writes `.env.template` verbatim, and the values are later consumed by Docker Compose
  interpolation. Runtime safety for recipe values comes from the af-api input-validation boundary,
  not from this catalogue. A declared `default` containing shell metacharacters or newlines is
  therefore either an injection-unsafe value or, at best, an authoring mistake — catch it at
  recipe-author time rather than relying on a downstream consumer to neutralise it.

### 3.5 docker-compose.yaml (skipped for `native`)

#### `compose-valid-yaml`

- **Level:** ERROR
- **What:** `docker-compose.yaml` parses as YAML.
- **How to check:** `yaml.safe_load`.
- **Why:** Same as `metadata-valid-yaml`.

#### `image-tag-pinned`

- **Level:** ERROR
- **What:** Every `image:` value has an explicit tag, and the tag is not `latest`.
- **How to check:** Regex `image:\s*(\S+)` over the file. For each match, fail if it ends with `:latest` or contains no `:` after a `/`.
- **Why:** Reproducibility (see `app-version-pinned`); also makes WUD diffs meaningful.

#### `compose-var-has-placeholder`

- **Level:** ERROR
- **What:** Every `${VAR}` reference in `docker-compose.yaml` corresponds to a `{{VAR}}` placeholder in `.env.template`.
- **How to check:** Regex `\$\{(\w+)\}` over compose, set-difference against template placeholders.
- **Why:** Compose substitutes empty string for undefined variables silently — produces broken containers, no error.

#### `bind-mount-under-opt`

- **Level:** WARN
- **What:** Every host bind mount path either starts with `/opt/<slug>/` or is on the exemption list.
- **How to check:** For each `services.*.volumes[]` entry, split on `:`. If host path starts with `/`, check prefix `/opt/<slug>/` or membership in the exemption list.
- **Exemption list:** `/var/run/docker.sock`, `/etc/localtime`, `/etc/timezone`, `/run/udev`.
- **Why:** Customer VMs use `/opt/<slug>/` as the per-app data root; backups, support, and migration tooling all assume this convention.

#### `no-public-db-port`

- **Level:** ERROR
- **What:** No service publishes a database port on the host.
- **How to check:** For each `services.*.ports[]` entry, parse the host port. Fail if the host port is in the forbidden list.
- **Forbidden host ports:** `3306` (MySQL), `5432` (PostgreSQL), `27017` (MongoDB), `6379` (Redis), `5984` (CouchDB), `9200` (Elasticsearch), `9042` (Cassandra), `1433` (MSSQL), `1521` (Oracle).
- **Why:** Databases on internet-reachable ports are an immediate security incident. They communicate over the internal bridge network only.

#### `no-privileged-without-justification`

- **Level:** WARN
- **What:** No service has `privileged: true` unless `metadata.notes` explicitly justifies it.
- **How to check:** For each service, if `privileged: true`, require a non-empty `metadata.notes` field.
- **Why:** Privileged containers expand the blast radius on shared customer VMs; justification forces conscious decision.

#### `service-has-healthcheck`

- **Level:** WARN
- **What:** Every service defined in `docker-compose.yaml` has a `healthcheck:` key.
- **How to check:** For each service, presence of `healthcheck`.
- **Why:** Without a healthcheck, `depends_on: condition: service_healthy` cannot work, and the install loop has no signal.

## 4. Cross-recipe rules

These rules apply to the catalogue as a whole — running over all `recipes/*/` directories.

#### `no-duplicate-public-port`

- **Level:** ERROR
- **What:** No two recipes declare the same `(port, protocol)` combination as a **host-bound** public port, except for ports `80` and `443`.
- **How to check:** Iterate all recipes, collect `metadata.ports[]` entries with `public: true` that are **not** Traefik-routed (i.e. `http: false`, or any `udp` port). Group by `(port, protocol)`. Any group of size > 1 (excluding 80/443) is a conflict.
- **Why:** Two co-installed recipes on the same VM cannot both bind the same host port.
- **HTTP/Traefik exception:** HTTP ports (`http: true`, the default) are reached through the per-VM Traefik reverse proxy at `<app-id>.<base_domain>` on 80/443 and never bind their declared port on the host — so any number of recipes may share e.g. `tcp/8080`. Only raw services (`http: false`) actually bind the host and can collide. The literal `80`/`443` carve-out remains for Traefik's own entrypoints.

#### `http-port-must-be-tcp`

- **Level:** ERROR
- **What:** A public port marked `http: true` (or defaulting to it) must use `protocol: tcp`.
- **Why:** Traefik's HTTP router cannot subdomain-route UDP. A public UDP port must set `http: false` (it is a raw host-bound service).

#### `incompatibility-ref-valid`

- **Level:** ERROR
- **What:** Every entry in `metadata.incompatible_with_apps` is a slug that exists in the catalogue.
- **How to check:** Per recipe, set-difference `incompatible_with_apps` against the list of all recipe directory names.
- **Why:** Phantom references mean the AF API cannot enforce the incompatibility — the constraint silently disappears.

## 5. Self-check procedure (for the AI agent)

When the `af-create-recipe` skill (or any other recipe-authoring tool) finishes generating a recipe, it should walk RFC-002 in the order above and emit one finding per rule that fails. The output structure for the developer:

```
Recipe: <slug>

Per-recipe checks
  files-required-compose          ✓
  metadata-valid-yaml             ✓
  app-version-pinned              ✓
  image-tag-pinned                ✗ ERROR — image 'redis:latest' on service 'redis'
  http-port-must-be-tcp           ✓
  bind-mount-under-opt            ⚠ WARN  — bind mount '/var/lib/postgres' should be under /opt/<slug>/
  ...

Cross-recipe checks
  no-duplicate-public-port        ✓
  incompatibility-ref-valid       ✓
```

A recipe is **ready for handoff** when there are zero ERROR-level findings. WARN-level findings are reported but do not block; the developer decides.

`af-validate` from af-core emits findings tagged with the same slugs. That gives parity between agent self-check, CI logs, and human review without two divergent rule lists.

## 6. Maintenance sweep

When a rule in this RFC changes (added, modified, removed), the change should land alongside a sweep of all existing recipes against the new ruleset. The intent: never let RFC-002 drift away from the catalogue.

The `af-update-recipes` skill (in `.claude/skills/`) implements this sweep — pointed at the rule diff (or a single rule, or the full catalogue), it walks the recipes, surfaces findings grouped by recipe, and drafts per-recipe fix patches for ERROR findings. The developer reviews each diff and ships one PR per affected recipe.

## 7. Rule lifecycle

- Rules may be **added** in a PR that lands the rule and any catalogue fixes triggered by it together.
- Rules may be **removed** (or downgraded ERROR → WARN) in a PR that explains why the rule is no longer load-bearing.
- Slugs are **never reused**. A removed rule's slug stays retired — if the same conceptual rule comes back with different semantics, give it a different slug.
- A rule may be **renamed** if its existing slug becomes misleading. In that case the PR maps the old slug to the new in af-core (so old logs are still grep-able for one release), and updates this RFC.

## 8. Open items

- [ ] CI integration: catalogue check runs on every PR to af-recipes, fails on any ERROR.
- [ ] A few rules are aspirational (`param-referenced` grep heuristic, `incompatibility-ref-valid` phantom refs) — they need precise pseudo-code if a second implementer tries to write them.
