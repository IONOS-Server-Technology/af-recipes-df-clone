# Contributing to af-recipes

This repository holds the App Factory recipe catalogue. Each recipe is a directory
under `recipes/<id>/` that describes a deployable application — its metadata,
compose file, install script, health check, and logo.

The authoritative specs live in [`rfc/`](rfc/):

- [`rfc/001-recipe-schema.md`](rfc/001-recipe-schema.md) — every `metadata.yaml`
  field and the logo specification (§4.6).
- [`rfc/002-recipe-rules.md`](rfc/002-recipe-rules.md) — the `af-validate` rules
  enforced in CI.

This guide is the practical how-to. When in doubt, the RFCs win.

## Anatomy of a recipe

```
recipes/<id>/
├── metadata.yaml      # catalogue metadata, parameters, logo fields
├── docker-compose.yaml# (recipe_type: docker-compose) the stack
├── install.sh         # docker-compose: prep only (compose-up.sh starts the stack); native: full install — see RFC-001 §9
├── health-check.sh    # readiness probe (see docs/health-check-spec.md)
└── logo.svg           # the application logo — see below
```

`id` must be lowercase kebab-case and match `metadata.id` and the directory name.

## Adding or changing a recipe

1. Copy an existing recipe of the same `recipe_type` as a starting point
   (e.g. `recipes/n8n/` for docker-compose apps).
2. Fill in `metadata.yaml` — see RFC-001 for every field. Key rules:
   - Parameter names are `UPPER_SNAKE_CASE` and must be referenced in
     `.env.template`, the compose file, or `install.sh`.
   - `auto_generate: true` is only valid on `type: password` parameters.
   - Record where you adapted the compose file from in `compose_file_url` /
     `compose_file_notes` — a direct link to the file, pinned if upstream offers
     a tag, and `null` plus a reason when no official one exists (RFC-001 §4.7).
   - Bump `recipe_version` (semver) on **any** change to a published recipe.
3. Add a logo (see the next section) for any `enabled: true` recipe.
4. Validate locally before opening a PR:

   ```bash
   af-validate recipes/<id>
   ```

5. Open a PR. The [`recipe-pipeline.yaml`](.github/workflows/recipe-pipeline.yaml)
   workflow uploads changed logos to the `appfactory-dev` bucket, runs
   `af-validate`, and checks every `logo_url` is reachable. On merge to `main` the
   same workflow mirrors logos to the production `appfactory` bucket.

> **`enabled` gates customer visibility.** A recipe with `enabled: false` does not
> appear in the catalogue and is **exempt** from the logo-required rule — useful
> for work-in-progress recipes. Flip it to `true` only once it has a valid logo
> and passes validation.

## Adding a logo

Every customer-visible (`enabled: true`) recipe **must** have a logo. Logos are
stored in git and mirrored to IONOS Object Storage by CI; see
[`docs/buckets.md`](docs/buckets.md) for the storage details.

### 1. Source an SVG

- **SVG only** — PNG and WEBP are rejected by `af-validate` and the upload job.
  SVG scales without quality loss across control-panel rendering densities.
- Square or near-square aspect ratio renders best as a thumbnail.
- Prefer the official logo from the upstream project (their press/brand kit,
  GitHub repo, or Wikimedia Commons). **Do not recolor, distort, or restyle it** —
  most app logos are trademarks; we display them unmodified to *identify* the app,
  not to brand our own product.

### 2. Place the file

Save it as exactly:

```
recipes/<id>/logo.svg
```

### 3. Compute the SHA-256

```bash
sha256sum recipes/<id>/logo.svg
```

### 4. Fill in the logo fields in `metadata.yaml`

```yaml
# Logo (rendered in app catalogue thumbnails)
logo_url: https://appfactory.s3.eu-central-3.ionoscloud.com/recipes/<id>/<recipe_version>/logo.svg
logo_sha256: <the sha256sum output>
logo_license: CC-BY-SA-4.0
logo_source: https://commons.wikimedia.org/wiki/File:Example-logo.svg
```

| Field | Required | Notes |
|---|---|---|
| `logo_url` | when `enabled: true` | Must match the canonical pattern exactly. The `<id>` and `<recipe_version>` in the path **must equal** this recipe's own `id` and `recipe_version`. Production host only (`appfactory.s3...`), `.svg` only. |
| `logo_sha256` | when `logo_url` set | 64-char lowercase hex. CI recomputes it from the file and fails on mismatch. |
| `logo_license` | when `logo_url` set | An SPDX identifier (`MIT`, `Apache-2.0`, `CC-BY-SA-4.0`, …) **or** the sentinel `trademark-nominative-fair-use` when the logo is a third-party trademark shown under nominative fair use. |
| `logo_source` | recommended | Attribution URL — the upstream page/repo the logo came from. Required in practice for attribution licenses (`CC-BY*`). |

### 5. Bump `recipe_version` if you changed an existing logo

The S3 path is versioned by `recipe_version` and objects are served with
`Cache-Control: immutable`. **Changing a logo without bumping `recipe_version`
means consumers see the old cached logo forever** — so CI rejects a modified
`logo.svg` that isn't accompanied by a `recipe_version` change. (Brand-new logos
on a new recipe are exempt; there's nothing cached yet.)

### What CI enforces (RFC-002 §3.3)

All ERROR-level, only for recipes that declare a logo:

- `logo-required-when-enabled` — `enabled: true` ⇒ `logo_url`, `logo_sha256`,
  `logo_license` all present.
- `logo-url-canonical` — URL matches the canonical bucket/path pattern, and the
  id/version in the path match the recipe.
- `logo-file-exists` — `recipes/<id>/logo.svg` exists in the repo.
- `logo-sha256-matches` — `logo_sha256` equals the SHA-256 of the on-disk file.

## Logo licensing

The catalogue is customer-facing, so logo licensing matters. Two layers apply to
every logo, independently:

1. **The file's copyright license** (`logo_license`). For `CC-BY*` licenses,
   preserve attribution via `logo_source`; don't create derivatives (recoloring,
   redrawing) — that triggers ShareAlike and brand-guideline issues.
2. **Trademark.** Nearly every app logo is a trademark regardless of the file
   license. Displaying the **unmodified** logo to identify the app in the catalogue
   is nominative fair use. Do **not** imply IONOS partnership/endorsement, put it
   on merchandise, or restyle it.

When the only basis is trademark (no copyright grant), set
`logo_license: trademark-nominative-fair-use`. For anything beyond a neutral
in-product catalogue (marketing/shop surfaces), or for awkward cases (e.g. a logo
inheriting a software copyleft license like AGPL), get legal sign-off — see the
licensing review on IF-712 for precedent.
