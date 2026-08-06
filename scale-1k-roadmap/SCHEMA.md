# `apps-gaps/<slug>.yaml` schema

Reference for gap-analysis issues run against Hostinger catalogue candidates
(see `new-app-candidates.csv` in the dark-factory operator directory). Each
issue researches one app and writes exactly one file here — no recipe files,
no PR. This is analysis only, to triage which apps are worth a real
`af-create-recipe` pass.

The structure below is documented for humans; [`schema.json`](schema.json)
is the machine-checkable version (JSON Schema, applies directly to the
parsed YAML). Validate all files with:

```bash
pip install pyyaml jsonschema
python3 bin/validate-apps-gaps
```

## Why this exists: no customer-supplied parameters today

Confirmed against `IF-1420` (root-password projection, `generated_from:
"<algo>:ROOT_PASSWORD"`, branch `feature/IF-1420-generated-from`) and
`IF-1312` (Traefik `basic_auth` toggle, branch `feature/IF-1312-basic-auth`),
both still unmerged but representing the actual MVP mechanism:

- `/compose` does not accept arbitrary customer-supplied values. There is no
  form field, no API param — the JWE bootstrap token only carries what
  af-api derives itself.
- The **only** supported per-customer secret is a hash of their existing
  server root password, projected one of two ways:
  - `generated_from: "argon2:ROOT_PASSWORD"` (or `bcrypt`) on a `type:
    password` metadata parameter — the app's own login (Vaultwarden's
    `ADMIN_TOKEN` is the shipping example).
  - Traefik `basic_auth: true` on the app's public port — gates an app with
    no login of its own behind HTTP basic auth (n8n, WUD, OpenClaw,
    Open WebUI, Immich use this).
- Everything else (external API keys, OAuth tokens, arbitrary admin
  usernames/passwords, third-party account credentials) has **no input
  channel today**. A recipe can still declare such a parameter in
  `metadata.yaml` for documentation purposes, but no customer value ever
  reaches it.

Practical test for "installable via our recipe mechanism today":

| App needs at first boot | Installable now? |
|---|---|
| Just a domain | yes |
| Domain + one admin login → project root password into it | yes (`generated_from`) |
| Domain + no login, but should be gated | yes (Traefik `basic_auth`) |
| Domain + a fixed/default/hardcoded admin credential the app itself gives no way to change | yes — gate the whole app behind Traefik `basic_auth`; that's the actual auth boundary, so a weak or unchangeable credential *behind* it is no longer customer-facing risk (IF-1312). Don't treat "app ships a fixed default password" as a blocker on its own. |
| Domain + a random secret nothing customer-facing reads (DB password, JWT signing key) | yes — generate anything patternless server-side, customer never needs it |
| A CLI tool / local agent with no web UI at all | yes, as `recipe_type: native` (see `recipes/claude-code/`, `recipes/gemini-cli/`) — AF supports native/CLI recipes as a first-class type, not just `docker-compose` web apps. Don't mark an app down just for lacking a container or a web UI. |
| Domain + an external API key/token the app can't function without | **no** — no channel for the customer to supply it |
| Domain + OAuth app registration / third-party account linking | **no** |
| Multiple independent customer-chosen logins | **no** — root-password projection only covers one |
| Domain + an admin credential the app will only accept as a hash in an algorithm `generated_from` doesn't support yet (e.g. `pbkdf2`) | **not a hard no** — the supported-algorithm list (`argon2`, `bcrypt`) is extensible; flag as `blocked_on_platform` with the needed algo named, not `not_recommended`. Only a genuine requirement for the **plaintext** password (not any hash) is a structural blocker, since `generated_from` only ever carries a hash. |

## Schema

```yaml
slug: <from CSV>
name: <from CSV, display name>
source_description: <from CSV, Hostinger's description — verbatim>

upstream:
  url: <homepage or repo>
  repo_url: <github url if OSS>
  license: <SPDX id or free text>
  docker_image: <official image, or null if none>

version_health:
  latest_version: <tag/release>
  latest_release_date: <YYYY-MM-DD>
  release_cadence: active | slowing | sporadic | dormant
  eol_status: active | maintenance-only | archived | eol
  notes: <e.g. "repo archived 2025-11", "no release in 2 years but issues still triaged", "vendor announced EOL date">

catalogue_fit:
  categories: [<af category-like tags>]
  has_web_ui: true | false
  reverse_proxy_compatible: true | false  # single HTTP port, no extra raw ports needed, works fine behind Traefik on <slug>.<base_domain>
  overlaps_with: [<existing recipe slugs covering similar ground, [] if none>]
  differentiation: <1-3 sentences: what does this add beyond the current 24 recipes>
  usefulness: high | medium | low
  usefulness_rationale: <1-3 sentences>

installability:
  recipe_type_guess: docker-compose | native
  secrets_required_at_first_boot: [<list of env vars / setup-flow secrets the app needs — include a basic-auth gate credential here if the app has no login of its own and needs one, [] if truly none>]
  secrets_expressible_today:
    - secret: <name — must match an entry in secrets_required_at_first_boot>
      mechanism: generated_from_root_password | traefik_basic_auth | server_generated_no_customer_input
    # [] if secrets_required_at_first_boot is []. Do NOT add a placeholder
    # entry (e.g. "none_needed") when there's nothing to express — an empty
    # list already says that. Omit entries only for secrets that have NO
    # expressible mechanism — list those in blocking_issues instead.
  blocking_issues: [<concrete reasons this can't ship as a recipe today, [] if none>]
  installable_today: true | false
  recommendation: build_now | build_with_caveats | blocked_on_platform | not_recommended

summary: <2-4 sentence human-readable verdict tying the above together>
```

Notes:
- `secrets_expressible_today` lists only what *can* be handled; anything the
  app needs that has no mechanism goes in `blocking_issues` — keeps the
  "why not" reasoning explicit instead of implied by absence.
- **An app with no login of its own is not automatically secret-free.** If it
  needs a Traefik `basic_auth` gate to avoid sitting open on the internet
  (no built-in auth, e.g. Adminer), that gate's credential IS a secret
  required at first boot — list it in `secrets_required_at_first_boot` and
  give it a matching `secrets_expressible_today` entry with `mechanism:
  traefik_basic_auth`. The structured fields must agree with whatever the
  `summary` prose says about needing a mandatory gate; don't leave the
  arrays empty while the prose describes a required credential.
- `installable_today` is the sharp yes/no; `recommendation` adds the softer
  judgment call (e.g. `build_with_caveats` for an app that's installable but
  low-value, or `blocked_on_platform` for one that's high-value but needs
  IF-1420/1312 merged, or a real API-key input channel, first).
- `version_health.notes` and any elapsed-time framing ("N months since the
  last release") must be computed against **today's actual date**, not an
  assumed or remembered one — get it from the environment/system clock, not
  from training-data recall, and double check the arithmetic before writing
  it.
- No `analyzed_at`/worker metadata field — dark-factory's own issue/job
  records already carry that provenance; don't duplicate it in-file.
- **Aggressive EOL/dormant detection is correct and valued, keep doing it.**
  Flagging an app `not_recommended` purely because upstream has gone dark for
  years (no commits, no releases, image frozen) — even when the app would be
  *mechanically* installable — is exactly the signal this analysis is for.
  Don't soften `eol_status`/`release_cadence` findings to be diplomatic about
  an abandoned project; the whole point is catching that before a recipe
  ships on top of it.
- **When an app name is ambiguous (multiple distinct upstreams share it),
  say so explicitly.** Name a candidate `repo_url` as usual, but add a line
  to `blocking_issues` (or `version_health.notes` if otherwise
  installable) noting that the name is ambiguous and which other project(s)
  you considered and ruled out, so a human reviewer can catch a wrong pick
  without re-doing the search themselves.
