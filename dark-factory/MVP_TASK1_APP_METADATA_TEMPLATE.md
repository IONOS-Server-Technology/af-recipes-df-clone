Title: AF recipe metadata: {{name}} ({{slug}})

Research "{{name}}" (Hostinger catalogue slug `{{slug}}`) from scratch and
draft `recipes/{{slug}}/metadata.yaml` — task 1 of the MVP build-now
pipeline (metadata comes first because it decides the
ports/parameters/version that later tasks implement against). This task
only covers `metadata.yaml` — do NOT create `docker-compose.yaml`,
`.env.template`, `install.sh`, `health-check.sh`, or `logo.svg` (those are
later tasks). `enabled: false` (set below) keeps it non-customer-visible
even once merged, so there's no reason to hold this file back from `main`.

Hostinger's description: "{{source_description}}"

**This task is self-contained — it does not read or require
`apps-gaps/{{slug}}.yaml`.** An earlier version of this pipeline split
research (writing an `apps-gaps/*.yaml` file) from metadata-authoring into
two tasks; that split is gone. Do your own upstream research directly, per
steps 1-4 below, and write straight to `metadata.yaml`. If an
`apps-gaps/{{slug}}.yaml` happens to exist from an earlier pass, you may
skim it for a pointer, but treat every fact in it as unverified — confirm
it yourself against upstream before relying on it. This has already caught
real mistakes: a prior `catalogue_fit.categories` free-text value copied
verbatim produced an invalid `metadata.yaml` category twice.

## What to do

1. Research upstream directly: official docs, the official Docker image
   and its currently-recommended tag, what ports the app exposes, what it
   needs to boot (database, cache, env vars), and its release history
   (latest release, cadence, whether it's active / maintenance-only /
   archived / EOL — use today's date, {{today}}, not a recalled one, for
   this). `.claude/skills/af-create-recipe/SKILL.md` Phase 2 is the
   method; follow it, don't invent your own.

2. Check 2-3 structurally similar existing recipes under `recipes/` (see
   Phase 2's heuristics for picking similar ones) to judge overlap with
   what we already have and to borrow a proven structural template — see
   step 5.

3. **Evaluate installability under the current recipe mechanism
   constraint — this decides whether this task can produce a usable
   metadata.yaml at all, so do it before drafting anything.** `/compose`
   does not accept any customer-supplied value at all — no form field, no
   API param. The only two supported per-customer secret channels are:
   - `generated_from: "<algo>:ROOT_PASSWORD"` (`argon2` or `bcrypt`) on a
     `type: password` parameter — **only works if the app's own
     login/config mechanism can consume an already-hashed value directly**
     (e.g. `install.sh` writing a bcrypt hash straight into a config field
     the app reads as a precomputed hash — this pattern works, check
     similar existing recipes under `recipes/` for a working example). It
     does **not** work for any app whose own bootstrap takes a *plaintext*
     password and hashes it itself internally (a CLI installer, a
     `createsuperuser`-style command, the app's own `bcrypt.hash()` call at
     first boot) — `generated_from` can only ever emit an already-hashed
     string, never plaintext, so feeding it into a plaintext-expecting
     installer just sets the literal hash string as the (unusable) new
     password. This is a confirmed, currently-unfixed platform limitation,
     not something to work around — if the app's admin account can only be
     set via a plaintext-taking installer, `generated_from` cannot cover
     it. Check which shape the app actually is before assuming
     `generated_from` will work.
   - Traefik `basic_auth: true` on the app's public port — only for a
     frontend with **no login of its own** (RFC-001 §4.3.1). If the app has
     its own login page, `basic_auth` in front of it is redundant, not a
     substitute for covering the app's own credential.

   Anything else — an external API key, OAuth registration, a customer
   -chosen credential, an app-specific admin password with **no**
   relationship to the root password and no login-less frontend to gate
   with `basic_auth` — has no input channel today.

   **Default: any web UI port without a customer-known login credential
   gets `basic_auth: true`.** There's no fixed product stance on the
   security/UX trade-off here, so this is the default until one exists.
   "Customer-known" means covered by a working `generated_from:
   "<algo>:ROOT_PASSWORD"` — nothing else counts: not a randomly
   `install.sh`-generated password, not the app's own self-service signup
   wizard, not an optional/blank-by-default site password. If the port
   isn't already covered by a working `generated_from` parameter, set
   `basic_auth: true` on it — don't invent a parameter or a delivery
   mechanism for a password the customer was never going to receive
   anyway; if the app's own credential is optional/leave-blank, don't
   declare it as a `parameters[]` entry at all, just leave it at its
   disabled default and let `basic_auth` cover the port. Add a comment
   telling the customer to run `/root/auth.sh off {{slug}}` once they've
   claimed/configured the app (check an existing recipe with a similar
   auto-generated, non-customer-input password for the exact comment
   shape). The only exception: don't stack `basic_auth` on a port
   `generated_from` already covers — redundant, not extra safety.

   **A customer-facing credential that install.sh must "just generate
   itself" (`openssl rand` or similar) is NOT a valid third mechanism,
   even though it looks like it works.** There is currently no channel in
   `af-api` to hand a value generated this way back to the customer after
   install — it gets written to disk and becomes permanently unreachable.
   This exact mistake has already shipped in real recipes before this rule
   existed, in two shapes: a standalone independent secret with no
   relationship to the root password, and (a variant of the same root
   cause) an app whose own installer takes plaintext, hashed internally,
   where `generated_from` looked applicable but structurally can't work
   (see the rule above). `install.sh` generating its **own internal**
   secrets (a JWT signing key,
   a session secret, a database password) is fine and expected — the
   distinguishing question is whether a *customer* ever needs to know the
   value to use the app, not whether the value needs to exist.

   **If this app's admin/login credential doesn't cleanly resolve to one
   of the two working mechanisms above, stop drafting metadata.yaml.**
   Report exactly what's missing (name the parameter, name the specific
   reason: plaintext-only installer / no login-less frontend to gate /
   independent secret with no relationship to root password) and treat
   this app as **not installable today** rather than writing a
   metadata.yaml that would ship a credential the customer can never
   learn. That is a complete, correct outcome for this task — do not paper
   over it by generating the value anyway.

4. **Version — do not pin by default (IF-1501).** Check whether the
   upstream project publishes its own official docker-compose file:
   - If it floats a tag (e.g. an `${APP_VERSION:-stable}`-style default,
     or a rolling alias), adopt that exact expression as `app_version` —
     don't resolve it to a pinned number yourself.
   - If it digest-pins or version-pins its own file, adopt that same pin.
   - If no official compose file exists, pick the current latest stable
     release tag from the project's releases page or Docker Hub — this is
     the one case where you do pick a fresh value, since there's no
     upstream choice to copy.
   Never use the literal string `latest`.

5. Pick a structural template from `recipes/` based on step 2's
   comparisons — whichever existing recipe matches this app's shape
   (single-container web app, Postgres/Redis-backed, multi-service stack,
   native/no-Docker) closest.

6. Decide `ports[]`: at minimum the app's web UI port (`http: true`,
   `public: true`), per `rfc/001-recipe-schema.md` §4.3. Use the chosen
   template recipe to confirm the right port, and whether `basic_auth:
   true` is warranted — check both step 3 triggers: a login-less frontend,
   and (separately) an unclaimed self-service setup wizard.

7. Decide `parameters[]`. Every `type: password` parameter must resolve to
   exactly one of these, and your report (see below) must state which for
   each one:
   - `generated_from: "<algo>:ROOT_PASSWORD"` — customer-facing, covered.
   - covered by this port's `basic_auth: true` — customer-facing, covered,
     the app's own login is irrelevant because `basic_auth` gates access
     before it's ever reached.
   - an internal-only secret (database password, JWT/session/signing key)
     that the customer never needs to know — fine for `install.sh` (task
     2) to generate independently; say so explicitly in the parameter's
     `description` so nobody mistakes it for an uncovered customer-facing
     credential later.
   If a parameter doesn't fit any of these three, you should have already
   stopped at step 3 — don't reach this step with an unresolved one.

8. Set `app_min_ram_mb` / `app_min_disk_mb` from the chosen template
   recipe's own values, adjusted only if upstream's docs state a
   materially different requirement.

9. Set `enabled: false` (not customer-visible until later tasks complete
   and a human flips it) and `recipe_version: 0.1.0`. Leave every `logo_*`
   field unset.

10. `categories:` must only use values from this exact list (confirmed
    against `af-api`'s real schema): `automation`, `ai`, `developer-tools`,
    `media`, `productivity`, `security`, `networking`, `storage`,
    `monitoring`, `home`, `communication`, `finance`, `education`,
    `gaming`, `utilities`, `infrastructure`. `database` is not in this
    list — `developer-tools` is usually the right fit for those.

11. Write the file to `recipes/{{slug}}/metadata.yaml`. Create no other
    file. Commit only this file.

12. **Self-check for valid metadata before finishing.** Go field-by-field
    against `rfc/001-recipe-schema.md` §4 (the field reference) and
    `rfc/002-recipe-rules.md`'s metadata-only rule subset —
    id-matches-directory, app-version-pinned, recipe-version-semver, the
    ports/parameters shape rules. Full cross-file rules
    (`compose-var-defined-in-env` etc.) don't apply until Task 2 exists,
    so don't try to satisfy those here. There's no local copy of
    `af-api`'s JSON Schema to validate against directly (`af-api` is a
    separate, private repo this project's worker has no credentials for —
    don't try to fetch it, it will 404) — this manual pass against the two
    RFC docs is the check available to you; `af-validate-rfc002` in CI is
    the real gate. Fix anything this surfaces before writing your final
    report.

## Report back — always, even if nothing was written

State explicitly, so a human can review without re-deriving your work:
- upstream source(s) used (docs URL, repo, Docker image + tag) and version
  health (active / cadence / EOL)
- which template recipe(s) you used and why
- the exact `app_version` chosen, and which of the three version rules
  above applied
- the port(s) chosen and whether `basic_auth` was set, and why — including
  whether the app has an unclaimed self-service setup wizard and how that
  was handled
- **for every `type: password` parameter: which of the three mechanisms in
  step 7 covers it, and for `generated_from` specifically, confirmation
  that you checked the app can consume an already-hashed value (not just
  that it has an admin password at all)**
- if you stopped at step 3: exactly which parameter blocked, and which of
  the three named reasons applied — report this as the task's complete
  outcome, not a failure

## This is enforced, not just requested

The `af-validate-rfc002` CI job runs the real `af-validate` CLI (the full
RFC-002 rule set, not just the JSON Schema) against this file once it's
part of a PR — step 12's self-check catches the same class of problem
early, it doesn't replace that gate. It does **not** catch the
password-delivery class of bug described in step 3 — that has no
automated check yet, which is exactly why step 3 exists.
