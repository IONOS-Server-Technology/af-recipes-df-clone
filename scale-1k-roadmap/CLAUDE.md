# hostinger-apps (dark-factory)

Triage pipeline: take Hostinger's public VPS application catalogue, evaluate
each app against Application Factory's (AF) recipe pipeline, and produce a
prioritized shortlist of what to build next. This is analysis-only — no
recipe files or PRs are produced here. Output feeds AF's product/catalogue
decisions (Andre) and engineering backlog (recipe-format changes needed to
unblock apps that don't fit today).

Related: `image-factory/app-factory` (the actual AF product repo/docs) and
Confluence page 670664397 ("Applications" — AF candidate list vs. Coolify/
DigitalOcean/Hetzner/Cloudron/Installatron). That page's competitor set does
**not** include Hostinger — this directory is the Hostinger-specific pass.

## Data lineage

1. **Source**: `https://www.hostinger.com/applications` — server-rendered
   HTML, ~1013 apps (name, slug, description only; category/"application
   type" is client-side-only data, not in the static HTML, and not worth
   chasing — see caution below).
2. **`hostinger-applications.csv`** — raw scrape, one row per app
   (`name,slug,description`). Copy of the same data also lives in
   `image-factory/app-factory/hostinger-applications.{yaml,csv}`.
3. **`new-app-candidates.csv`** (997 rows) — the raw scrape minus apps AF
   already covers. This is the input list, one issue per row.
4. **`processed-slugs.txt`** (997 lines) — tracks which candidates have
   been run through the analysis pipeline. Should match
   `new-app-candidates.csv` row count when a full pass is complete.
5. **`apps-gaps-full-export.csv`** (997 rows, 26 columns) — the merged
   analysis output, one row per candidate app. Schema per row: upstream
   URL/repo/license/Docker image, version health (`latest_version`,
   `release_cadence`, `eol_status`), `categories`, `has_web_ui`,
   `reverse_proxy_compatible`, `overlaps_with` / `differentiation` vs.
   existing AF recipes, `usefulness` + rationale, `secrets_required_at_first_boot`
   / `secrets_expressible_today` / `blocking_issues`, `installable_today`
   (bool), and a final `recommendation`.
   - `installable_today`: 670 true / 327 false
   - `recommendation`: build_now 221, build_with_caveats 356,
     blocked_on_platform 212, not_recommended 208
6. **`top-candidates-build-now.csv`** (98 rows) — curated shortlist derived
   from the export, clustered by product category (`cluster` column).
   Largest clusters: Standalone (37), Storage (8), CMS (7), Media library
   (7), Finance (6), Notebook/dev env (5), Finance-adjacent ERP (4),
   Kanban (4), Wiki (4).
7. **`apps-gap-analysis-DRAFT.md`** — the design doc for this whole
   pipeline (methodology, schema, the constraint below). Written as a draft
   for review; the pipeline described in it has since been run (outputs
   above exist).

## The constraint that shapes every "installable_today" verdict

AF's `/compose` endpoint (JWE bootstrap token) does not accept arbitrary
customer-supplied values — no form field, no API param. Confirmed against
`IF-1420` (root-password projection) and `IF-1312` (Traefik basic_auth
toggle), both unmerged but representing the actual MVP mechanism. The
**only** supported per-customer secret channels are:

- `generated_from: "argon2:ROOT_PASSWORD"` (or `bcrypt`) on a `type:
  password` metadata parameter — projects the customer's own server root
  password into the app's login (Vaultwarden's `ADMIN_TOKEN` is the
  shipping example).
- Traefik `basic_auth: true` on the app's public port — gates a login-less
  app behind HTTP basic auth (n8n, WUD, OpenClaw, Open WebUI, Immich use
  this).

Anything needing an external API key/OAuth token/third-party account link,
or multiple independent customer-chosen logins, has **no input channel
today** → `installable_today: false`, regardless of how good the app is.
This is why ~1/3 of candidates are blocked — it's a platform gap, not an
app-quality judgment. The two JIRA drafts below are the proposed fix path.

## Open follow-on work (drafted, not yet filed as tickets)

- **`jira-draft-compose-metadata.md`** (Draft 1 of 2) — add
  `compose_file_url` / `compose_file_notes` to `metadata.yaml` so every
  recipe records which upstream compose file it derives from.
- **`jira-draft-recipe-resync.md`** (Draft 2 of 2, depends on Draft 1,
  referenced as `IF-1500`) — for all 22 existing recipes, find upstream
  compose source and resync versions/structure to match it. Policy:
  **adopt upstream's own pinning choice as-is** (float if they float, e.g.
  n8n's `${N8N_VERSION:-stable}`) — `test-recipes-live` CI is the safety
  net, not a hand-pin. Also check structural drift (ports, `cap_drop`,
  `no-new-privileges`, healthchecks), not just versions — openclaw is
  flagged as already drifted from its real upstream file.

## Caution: Hostinger scraping

Cloudflare rate-limits (Error 1015) aggressively. A prior session got the
user's IP temporarily banned after a handful of requests beyond the single
initial page fetch (trying to chase per-app category data via detail pages
and repeated fetches). Rules going forward:
- **One fetch per refresh, nothing more.** Don't try to enrich via
  additional requests (detail pages, filter/category endpoints) — that
  data is client-side only and not worth the risk.
- If a fresher catalogue snapshot is needed, have the user save the
  fully-rendered page from their own browser (Ctrl+S → "Webpage,
  complete") and hand over the local file — parse that, zero requests.
- Diff any new snapshot against the current `new-app-candidates.csv`
  before regenerating anything — the catalogue drifts over time (one
  observed diff: +Ente, +Fleetbase, +Frigate / -InvenTree, -Jitsu between
  two snapshots ~9 days apart). Only re-run the analysis pipeline for
  genuinely new slugs, not the whole set.

## `.claude/settings.local.json`

Local permission allowlist for this dir: `Bash(python3 *)`,
`mcp__atlassian__jira_get_issue`, `WebSearch`, `WebFetch(domain:
raw.githubusercontent.com)`, `WebFetch(domain:github.com)` — i.e. this
pipeline's per-app research step fetches upstream docs/READMEs/release
pages, not Hostinger itself.
