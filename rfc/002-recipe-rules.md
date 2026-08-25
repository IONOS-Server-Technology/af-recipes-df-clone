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
- The `af-validate` CLI in [af-api](https://github.com/IONOS-Server-Technology/af-api) — enforces these rules in CI
- Future maintenance sweeps — when a rule changes here, every existing recipe is re-checked against the new version

If a rule cannot be expressed concretely enough to be machine-checked, it does not belong in this RFC — it belongs in style notes.

## 2. Rule format

Each rule has:

- **ID** — a stable, descriptive slug (`no-public-db-port`, `bind-mount-under-opt`, …). Stable; never reused. Slugs are chosen to read like assertions, so a finding line in agent output or CI log is intelligible without looking up this RFC.
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

#### `health-check-waits`

- **Level:** WARN
- **What:** A `docker-compose` recipe's `health-check.sh` must wait for the application to come up, not probe it once.
- **How to check:** Strip comment lines, then require both a loop keyword (`while`, `until`, `for`) and a `sleep`. Not checked for `recipe_type: native`.
- **Why:** IF-1440 — twelve recipes curled once, immediately after `docker compose up -d`, so their PR-gate test failed for eight days without anyone noticing. Fifteen red marks per pull request are noise, not a signal, and none of those recipes had working coverage at all.
- **Deliberately not prescribed:** *how* it waits. Two shapes are in the tree and both are correct — polling the containers' Docker health status, or falling back to a localhost URL and retrying it with a ceiling. A rule naming one of them would fail three recipes that work, which is the mistake `param-referenced` had to be rewritten to avoid.
- **Why WARN:** `health-check.sh` is not part of the install archive, so a bad one misleads the next author and wastes CI time but never reaches a customer. Whether the recipe tests should block a merge at all is a separate, open decision (IF-1440).

### 3.2 metadata.yaml

#### `metadata-valid-yaml`

- **Level:** ERROR
- **What:** `metadata.yaml` must parse as YAML.
- **How to check:** `yaml.safe_load`. If it raises, fail.
- **Why:** Everything downstream assumes a parseable document.

#### `metadata-schema-valid`

- **Level:** ERROR
- **What:** The parsed metadata must satisfy [`metadata.schema.json`](https://github.com/IONOS-Server-Technology/af-api/blob/main/src/af_api/core/schema/metadata.schema.json).
- **How to check:** `jsonschema.validate(metadata, schema)`.
- **Why:** The AF API loads recipes against this schema at startup; a recipe that fails the schema crashes the API.

#### `id-matches-dir`

- **Level:** ERROR
- **What:** `metadata.id` must equal the recipe directory name.
- **How to check:** String comparison.
- **Why:** The directory name is the slug used everywhere (URLs, `incompatible_with_apps`, install paths). Divergence breaks lookups.

#### `app-version-pinned` — RETIRED (IF-1500)

- **Level:** ~~ERROR~~ — retired, no longer checked.
- **What it was:** `metadata.app_version` must not be `latest` (case-insensitive).
- **Status:** Retired with `image-tag-pinned` when we adopted upstream's versioning (§3.5).
  A recipe whose image floats has no pinned version to name, so `latest` or `stable` became
  the honest value for the field rather than a defect. Nothing parses `app_version` — it
  reaches the `/catalogue` response and the compose token and is read by neither — so the
  rule protected a property no code depended on. Slug retired, never reused.

#### `recipe-version-semver`

- **Level:** ERROR
- **What:** `metadata.recipe_version` matches `^\d+\.\d+\.\d+$`.
- **How to check:** Regex.
- **Why:** Allows mechanical bumping when this recipe (not the upstream app) changes.

#### `curated-requires-enabled`

- **Level:** ERROR
- **What:** `metadata.curated: true` requires `metadata.enabled: true` (RFC-001 §4.8).
- **How to check:** `if meta.get("curated") and not meta.get("enabled")` → fail.
- **Why:** `POST /api/v1/compose` rejects a disabled recipe, so the nightly regression run could never deploy a curated-but-disabled one — the pair is a nightly that can only fail, and the flag is silently doing nothing until someone notices.

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

#### Icon spec rules (IF-1416)

The rules below enforce the design requirements from [IF-1416](https://hosting-jira.1and1.org/browse/IF-1416): **SVG format, square viewBox, image centred with excess whitespace minimized, transparent background, primary colour version only.** They run against `recipes/<id>/logo.svg` whenever `logo_url` is declared.

Eleven rules, plus a `logo-render-checks-skipped` notice that is not itself a rule. The first five need nothing beyond the standard library. The rest rasterize the SVG and measure the alpha channel, which requires the optional `af-api[logo]` extra (`resvg-py` + `pillow`, both MIT with pure wheels — no system packages). CI installs it via `uv pip install './af-api-src[logo]'` and passes `--require-logo-render`, which turns a missing renderer from a warning into an error — otherwise a broken install step would quietly reduce CI to the five structural rules while still reporting PASS.

Thresholds are constants in [`src/af_api/core/logo_validator.py`](https://github.com/IONOS-Server-Technology/af-api/blob/main/src/af_api/core/logo_validator.py); change them there, not in a recipe. Note the library lives in af-api since IF-1327 — the standalone af-core repo is frozen.

#### `logo-svg-wellformed`

- **Level:** ERROR
- **What:** `logo.svg` is at most 2 MiB, parses as XML, and its root element is `<svg>`.
- **How to check:** Reject above the byte ceiling, then parse with `xml.parsers.expat` and compare the root tag. Not `ElementTree`: expat lets us install an `EntityDeclHandler` that rejects entity declarations outright and an `ExternalEntityRefHandler` that refuses to resolve anything, so third-party artwork has no entity-expansion surface at all rather than a bounded one.
- **Why:** Everything downstream assumes a parseable SVG. A truncated or mislabelled file would otherwise fail at render time in the customer's browser. The size ceiling is a sanity check (the largest real logo is 71 KiB) and a second bound on expansion, behind the entity rejection above.

#### `logo-no-script`

- **Level:** ERROR
- **What:** No `<script>` or `<foreignObject>` element, no `on*` event-handler attribute, and no `javascript:`, `vbscript:` or `data:text/html` URI in an `href`, `src` or `url()` value.
- **How to check:** Walk the elements and attributes reported by the expat parse, and the text of any `<style>` element.
- **Why:** SVG is an executable XML document. A logo is third-party artwork rendered in the control panel, so it must carry no executable content — otherwise the catalogue becomes an XSS surface fed by upstream repositories. Checking the parse rather than the file source matters: expat has already decoded character references, so `&#106;avascript&#58;` is caught, whereas a regex over the raw bytes sees only the encoded form. A scheme in an `href` is the more likely payload of the two — `on*` handlers are the textbook example, but no real renderer needs either.

#### `logo-no-external-refs`

- **Level:** ERROR
- **What:** Every `href`, `src` and `url()` target is either an internal `#fragment` or a `data:image/` URI. No absolute URL, no relative path, no `@import` in a `<style>` element.
- **How to check:** Collect the same reference set as `logo-no-script` and reject anything that is neither a fragment nor an embedded image.
- **Why:** `logo.svg` is shipped on its own to S3 and rendered from there. A reference to `./icon.png` or `https://cdn.example/logo.png` therefore renders blank for the customer, and when it does resolve it discloses their IP and user agent to a third-party host on every catalogue page view. Fonts are the trap worth naming: an `@import` of a webfont looks harmless in a browser preview and turns into both problems in production.

#### `logo-viewbox-square`

- **Level:** ERROR
- **What:** A usable `viewBox` is present and its width equals its height (tolerance 0.01).
- **How to check:** Parse the `viewBox` attribute; compare the third and fourth values.
- **Why:** IF-1416 requirement 2. Without a `viewBox` the file cannot be scaled predictably; with a non-square one the mark renders distorted or off-centre in a square thumbnail. Both were real defects: `n8n` shipped 500×200 with no `viewBox`, `portainer` shipped 1064×131.

#### `logo-raster-embedded`

- **Level:** ERROR below 480px on the longest edge, otherwise WARN
- **What:** The SVG does not wrap a raster image. If it does, the embedded raster is at least 480px on its longest edge.
- **How to check:** Decode **every** `data:image/` payload and read the pixel size from the PNG `IHDR` or JPEG `SOFn` header; judge the file by the largest raster found, and say how many there were. An `<image>` element with no readable payload is an error on its own, unless `logo-no-external-refs` has already reported the same reference.
- **Why:** IF-1416 requirement 1 asks for SVG, and a PNG in an SVG wrapper satisfies the file extension while delivering none of the benefit. 480px is the floor at which a 256px tile still looks sharp at 2× DPI; below it the tile is visibly blurry. `open-webui` shipped a 500px raster this way and `hermes-agent` a 150px one. The WARN above the floor is deliberate: some projects publish no vector at all, so a good raster is allowed but never silent. Sizing on the largest raster rather than the first one encountered keeps the verdict independent of document order — a 1px spacer ahead of the real artwork must not decide the level.

#### `logo-safe-area`

- **Level:** ERROR outside 80–95%, WARN outside 87–93%
- **What:** The rendered ink occupies close to 90% of the canvas on its longest edge.
- **How to check:** Rasterize, threshold alpha at 12, take the ink bounding box, compare `max(w, h) / canvas` against the two bands.
- **Why:** IF-1416 requirement 2, "excess whitespace/padding minimized", made numeric. Before this, recipe logos ranged from 49% to 100% fill, so the catalogue grid looked ragged even though every file was individually fine. 90% leaves the mark clear of the tile edge. The band pattern is the same as `logo-mark-not-wordmark`: a hard ERROR at ±3 points would make every future recipe hand-fit a 6-point window to merge, and the number is a grid-framing choice rather than a defect boundary — so the ERROR marks artwork that is actually wrong (49% padding, 100% bleed) and the WARN carries the framing preference. It costs nothing in practice: all 17 safe-area errors on the pre-IF-1416 catalogue are outside 80–95% too, so relaxing the ERROR band loses no real finding.

#### `logo-centered`

- **Level:** ERROR
- **What:** The ink bounding box's centre is within 1.5% of the canvas centre, measured per axis.
- **How to check:** Compare the bbox midpoint with the canvas midpoint — the horizontal offset as a percentage of canvas width, the vertical offset as a percentage of canvas height.
- **Why:** IF-1416 requirement 2, "image centered". The tolerance absorbs asymmetric artwork; anything larger reads as misaligned when tiles sit next to each other. Both axes need their own divisor: a non-square canvas is already a `logo-viewbox-square` error, but dividing a vertical offset by the width understates it on a wide canvas and hid one genuinely off-centre logo in the pre-IF-1416 catalogue.

#### `logo-transparent-bg`

- **Level:** ERROR when a flat plate is detected, WARN for a solid multi-colour mark
- **What:** No opaque background plate behind the mark. ERROR when the ink bounding box is over 95% fully opaque **and** over 70% of it is a single flat colour; WARN when it is over 95% opaque but multi-colour.
- **How to check:** Rasterize; count pixels with alpha > 250; bucket their colours into 24-step RGB bins and take the largest bin.
- **Why:** IF-1416 requirement 4. Both conditions are required because opacity alone is not evidence of a plate — a solid geometric mark is legitimately 100% opaque. `wg-easy`'s asset was 98.3% opaque with 75.8% one colour (a real dark-red plate), while `portainer`'s brand tile is 99.1% opaque with only 52.4% dominant. Treating the second as an error would reject a mark the brand ships that way, so it is a WARN for a human to accept.

#### `logo-mark-not-wordmark`

- **Level:** ERROR outside 0.50–2.00, WARN outside 0.77–1.30
- **What:** The rendered ink's aspect ratio is close to square.
- **How to check:** Divide the ink bounding box width by its height.
- **Why:** IF-1416 requirement 2 says square "whenever possible". A wordmark or horizontal lockup padded into a square canvas renders as an unreadable sliver — `portainer` was 8.0:1, `claude-code` 4.65:1, `adguard-home` 3.94:1, `n8n` 3.66:1. The WARN band exists because some marks are genuinely non-square upstream (Pi-hole's Vortex is 0.68:1, Gitea's teacup 1.62:1) and no better asset exists.

#### `logo-contrast`

- **Level:** WARN
- **What:** The ink is neither near-white (luminance > 235) nor near-black (< 20).
- **How to check:** Rasterize; average relative luminance over the highest alpha threshold of (200, 128, 32) that covers at least 2% of the ink bounding box.
- **Why:** IF-1416 requirement 3 forbids a second colour variant, so a mark that vanishes against one tile background cannot be fixed inside the recipe — the consuming UI has to own the background. It is a WARN for that reason. Its more valuable job is catching the **wrong variant** being picked: `ollama` shipped the white `favicon.svg`, which is not merely low-contrast but invisible on a light tile. The stepped alpha threshold matters — averaging over `alpha > 32` dilutes a solid white mark with its anti-aliased edges and reported 77 instead of 255, while using only `alpha > 200` divides by an empty population for a soft gradient mark and reports a false 0.

#### `logo-renders`

- **Level:** ERROR
- **What:** The SVG rasterizes, and to something visible.
- **How to check:** Render it; fail if the renderer errors or the result has no pixels above the alpha threshold.
- **Why:** A file can be well-formed XML and still draw nothing — an empty `<svg/>`, a path with no geometry, or a single-stop gradient. Such a logo shows as a blank card. Artwork depending on an unfetched external resource is the same failure, caught earlier by `logo-no-external-refs`.

#### `logo-render-checks-skipped`

- **Level:** WARN, or ERROR under `--require-logo-render`
- **What:** Emitted once per recipe when the optional renderer is not installed.
- **How to check:** Attempt to import `resvg_py` and `PIL`.
- **Why:** The pixel-level rules are the ones that catch the defects a reviewer would notice. Silently skipping them would let a run report success having checked almost nothing, so their absence is always visible in the output. A developer running `af-validate` from a lean install gets the warning and the five structural rules; CI passes `--require-logo-render` so that the same condition fails the build instead — otherwise the verdict silently depends on the environment.

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
- **Status:** Never implemented, and its premise is gone — there is no render-time
  substitution (IF-944). It is superseded by `no-env-placeholder` below, which forbids the
  tokens outright rather than requiring them to be declared. IF-1390 (PR #49) retires this
  entry; if that lands first, this block disappears and only `no-env-placeholder` remains.

#### `no-env-placeholder`

- **Level:** ERROR when `metadata.enabled: true`, WARN otherwise.
- **What:** `.env.template` contains no `{{KEY}}` token, in any line including comments.
- **How to check:** Regex `\{\{(\w+)\}\}` over the whole file; one finding per distinct token.
- **Why:** The renderer copies `.env.template` to the VM's `.env` byte for byte, so a token
  arrives as literal text. A password left that way is identical on every VM in the fleet
  and readable from this repo; a hostname left that way is not a hostname. No other rule
  *implemented in af-validate* inspects env template values — `compose-var-defined-in-env`
  compares key names only, and `param-referenced` below does look at the tokens but was
  never implemented — which is why 63 unresolvable tokens sat in the catalogue while
  af-validate reported 24/24 clean, and why IF-1309 shipped a fleet-wide-identical
  dashboard password green.
- **What to write instead:** a literal for static config; an empty key the recipe's own
  `install.sh` fills for a per-VM secret; an empty key the customer fills for a value only
  they have; nothing at all for the app's own FQDN, which arrives as the platform's
  reserved `AF_APP_DOMAIN`.
- **Level rationale:** the same `enabled` split as `logo-required-when-enabled`. Only an
  enabled recipe reaches a customer, so only there is a leftover token a live defect; a
  disabled one is a migration backlog item. IF-1417 cleared every enabled recipe, which is
  what makes the ERROR half safe to switch on — before that it would have turned the whole
  catalogue red and blocked unrelated PRs. Raise the WARN half to ERROR once the 16 disabled
  recipes are migrated too, and this rule collapses back to a single level.

#### `param-referenced`

- **Level:** WARN
- **What:** Every `metadata.parameters[].name` is consumed somewhere in its own recipe.
- **How to check:** After dropping whole-line `#` comments from each file, the name counts as consumed if any of these holds — otherwise warn, once per parameter:
  1. it appears as `${NAME}` in `docker-compose.yaml` (or the legacy `docker-compose.yml`);
  2. it is a key in `.env.template` (`NAME=`);
  3. it appears as a whole word in `install.sh`.
- **Why:** Unreferenced parameters are typos or dead code. They cannot reach a customer — af-api strips the whole `parameters` block before parsing and `/compose` accepts none since IF-944 — but they mislead the next author, which is exactly how eight of them accumulated unnoticed (IF-1454).
- **Three deliberate narrowings**, each one required to catch a real case:
  - *The compose reference counts, not the definition.* `wg-easy` declared `WG_HOST` while its compose said `WG_HOST=${AF_APP_DOMAIN}`: the name is present, but the value comes from the platform, so the declared parameter was already dead. Matching the left-hand side would call that referenced.
  - *Comments do not count.* `ollama`'s `.env.template` states in prose that `OLLAMA_DEFAULT_MODEL` "is consumed by nothing" — a comment saying a parameter is dead must not be what keeps it alive.
  - *Whole word, not substring.* Otherwise `wg-easy`'s `ADMIN_PASSWORD` is satisfied by an unrelated `GITEA_ADMIN_PASSWORD`.
- **Superseded wording:** this rule used to say a parameter counts when it appears in `.env.template` as `{{KEY}}`. That is the exact form [`no-env-placeholder`](#no-env-placeholder) has flagged as a defect since IF-1417, so the two rules contradicted each other and the rule was unimplementable as written. Recipes ship a bare empty key instead, which is what condition 2 checks.

#### `generated-from-password-only`

- **Level:** ERROR
- **What:** `generated_from` is only allowed where `type: password`.
- **How to check:** For each parameter, if `generated_from` is present and `type != password`, fail.
- **Why:** The projected value is a password hash; it is only meaningful for secret-type fields. The `<algo>:<source>` grammar itself is enforced by the schema pattern, so an unsupported algorithm surfaces as `metadata-schema-valid`.

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

#### `image-tag-pinned` — RETIRED (IF-1500)

- **Level:** ~~ERROR~~ — retired, no longer checked.
- **What it was:** Every `image:` value has an explicit tag, and the tag is not `latest`.
- **Status:** Retired when the versioning policy changed. **A recipe now follows whatever its
  upstream reference does** — pinned where upstream pins, floating (`:latest` included) where
  upstream floats — applied per image, so a recipe may pin its database and float its app if
  that is what upstream does. The old rule contradicts that outright.

  It was not reworded into a conditional rule because the condition is not knowable here:
  whether a tag matches upstream is a fact about someone else's repository, and RFC-001 §4.7
  is explicit that `compose_file_url` is never fetched at build or run time. A rule that
  cannot evaluate its own predicate is worse than no rule. Comparison happens in the upstream
  sweep (§6) instead, by a human reading the reference.

  **What this gives up:** an accidentally untagged image — `image: myorg/app` with the tag
  forgotten — is no longer caught, because nothing local distinguishes it from a deliberate
  float. Reviewers own that now. Two consequences to keep in view, neither yet settled:

  - **WUD** compares tags, so a floating tag never reports an update. Watching digests
    (`wud.watch.digest`) would be needed for floating recipes; the label matrix in RFC-001
    §11 does not set it today.
  - **Nothing re-tests a floating recipe.** `test-recipes-docker` and `-live` run only on PRs
    touching `recipes/**` and on manual dispatch — no schedule — so a recipe validated at
    merge silently pulls untested images later. A periodic run over floating recipes is the
    obvious mitigation and belongs in its own card.

  Slug retired, never reused.

#### `compose-var-defined-in-env`

- **Level:** ERROR
- **What:** Every `${VAR}` reference in `docker-compose.yaml` corresponds to either a `VAR=` line
  in `.env.template` or one of the platform's reserved keys.
- **How to check:** Regex `\$\{(\w+)\}` over compose; regex `^(\w+)=` over template lines that are
  not comments; set-difference, then drop anything in the platform's allow-list
  (`AF_APP_DOMAIN`, prefix `AF_`).
- **Why:** Compose substitutes empty string for undefined variables silently — produces broken
  containers, no error. Checked by key name only, not by placeholder syntax: since
  `no-env-placeholder` already forbids `{{VAR}}` tokens outright, a recipe author declares the
  key as `VAR=` (empty or literal) instead of a placeholder. The `AF_` namespace is exempt
  because the platform writes those keys into `.env` at render time — only the API knows the
  value, e.g. the app's own FQDN as `AF_APP_DOMAIN` (IF-1417). Matched against an explicit
  allow-list rather than the bare `AF_` prefix, so a typo like `${AF_APP_DOMIAN}` still fails
  here instead of reaching the customer's VM as an empty interpolation.

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
- **What:** No two recipes declare the same `(port, protocol)` combination as a **host-bound** public port.
- **How to check:** Iterate all recipes, collect `metadata.ports[]` entries with `public: true` that are **not** Traefik-routed (i.e. `http: false`, or any `udp` port). Group by `(port, protocol)`. Any group of size > 1 is a conflict.
- **Why:** Two co-installed recipes on the same VM cannot both bind the same host port. Either change one host port, or list the conflict in `incompatible_with_apps` so the pair can never be selected together.
- **HTTP/Traefik exception:** HTTP ports (`http: true`, the default) are reached through the per-VM Traefik reverse proxy at `<app-id>.<base_domain>` on 80/443 and never bind their declared port on the host — so any number of recipes may share e.g. `tcp/8080`. Only raw services (`http: false`) actually bind the host and can collide.
- **No 80/443 carve-out:** earlier revisions exempted ports 80 and 443 outright, because HTTP recipes conceptually "use" Traefik's entrypoints. `http: true` now identifies exactly those recipes, so the carve-out is redundant for them — and actively harmful otherwise, since it would have exempted a *raw* binding on 80/443, the one case guaranteed to collide with Traefik itself. Those are rejected outright by `raw-port-not-reserved` below.

#### `http-port-must-be-tcp`

- **Level:** ERROR
- **What:** A public port marked `http: true` (or defaulting to it) must use `protocol: tcp`.
- **Why:** Traefik's HTTP router cannot subdomain-route UDP. A public UDP port must set `http: false` (it is a raw host-bound service).

#### `raw-port-not-reserved`

- **Level:** ERROR
- **What:** A public port with `http: false` may not use port `80` or `443`.
- **Why:** The per-VM Traefik container binds `80:80` and `443:443` on the host. A raw service claiming either would fail to start behind it. HTTP ports on 80/443 are fine — Traefik fronts them and they never bind the host (this is the runtipi shape).

#### `single-http-port`

- **Level:** WARN
- **What:** A recipe should declare at most one Traefik-routed port. Ports `80` and `443` declared together count as one endpoint (the "app terminates its own TLS" idiom).
- **How to check:** Collect `public: true` entries that are Traefik-routed. Collapse a declared 80/443 pair into a single entry. More than one remaining entry is a finding.
- **Why:** The renderer emits exactly one Traefik router per app, targeting the *first* Traefik-routed port in declaration order — but it strips the host binding of *every* routed port. A second routed port therefore ends up with neither a host binding nor a route, i.e. silently unreachable. Mark the extras `http: false`, or make them non-public.

#### `basic-auth-requires-routed-port`

- **Level:** ERROR
- **What:** A port with `basic_auth: true` must be Traefik-routed — `public: true`, `http: true` (or defaulted) and `protocol: tcp`.
- **How to check:** For each `metadata.ports[]` entry with `basic_auth: true`, verify all three conditions. Report which ones fail.
- **Why:** Basic auth is applied by attaching a middleware to the app's Traefik router, and that router only exists for a Traefik-routed port. On a raw or non-public port the flag has nothing to attach to, so it would read as "this frontend is protected" while protecting nothing — a silent security failure rather than a visible misconfiguration.
- **Note:** This is stricter than "must be public". A `public: true` port with `http: false` binds the host directly and has no router, so it is rejected too (IF-1312, refining the original wording which predates the `http` flag from IF-1401).

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
  http-port-must-be-tcp           ✓
  raw-port-not-reserved           ✓
  single-http-port                ✓
  basic-auth-requires-routed-port ✓
  bind-mount-under-opt            ⚠ WARN  — bind mount '/var/lib/postgres' should be under /opt/<slug>/
  ...

Cross-recipe checks
  no-duplicate-public-port        ✓
  incompatibility-ref-valid       ✓
```

A recipe is **ready for handoff** when there are zero ERROR-level findings. WARN-level findings are reported but do not block; the developer decides.

`af-validate` from af-api emits findings tagged with the same slugs. That gives parity between agent self-check, CI logs, and human review without two divergent rule lists.

## 6. Maintenance sweep

When a rule in this RFC changes (added, modified, removed), the change should land alongside a sweep of all existing recipes against the new ruleset. The intent: never let RFC-002 drift away from the catalogue.

The `af-update-recipes` skill (in `.claude/skills/`) implements this sweep — pointed at the rule diff (or a single rule, or the full catalogue), it walks the recipes, surfaces findings grouped by recipe, and drafts per-recipe fix patches for ERROR findings. The developer reviews each diff and ships one PR per affected recipe.

## 7. Rule lifecycle

- Rules may be **added** in a PR that lands the rule and any catalogue fixes triggered by it together.
- Rules may be **removed** (or downgraded ERROR → WARN) in a PR that explains why the rule is no longer load-bearing.
- Slugs are **never reused**. A removed rule's slug stays retired — if the same conceptual rule comes back with different semantics, give it a different slug.
- A rule may be **renamed** if its existing slug becomes misleading. In that case the PR maps the old slug to the new in af-api (so old logs are still grep-able for one release), and updates this RFC.

## 8. Open items

- [ ] CI integration: catalogue check runs on every PR to af-recipes, fails on any ERROR.
- [x] `param-referenced` was aspirational — a grep heuristic whose stated predicate contradicted `no-env-placeholder`. Implemented in IF-1454 with the three explicit conditions written out above.
- [ ] `incompatibility-ref-valid` (phantom refs) is still aspirational — it needs precise pseudo-code if a second implementer tries to write it.
