Title: Gap analysis: {{name}}

Research and analyze the self-hosted app "{{name}}" (Hostinger catalogue slug
`{{slug}}`) as a candidate for the IONOS Application Factory recipe catalogue.
This is analysis only — do NOT create recipe files, do NOT open a PR.

Hostinger's description: "{{source_description}}"

Today's date is {{today}}. Use this, not a recalled or assumed date, for any
release-cadence / time-since-last-release calculation in `version_health`.
{{rerun_note}}
## What to do

1. Read `.claude/skills/af-create-recipe/SKILL.md`, Phase 2 (Research) only,
   for the research method — upstream docs, official Docker image + pinned
   tag, ports, what the app needs to boot. Ignore Phases 1 and 3-5; this is
   not a recipe-authoring task.
2. Also check 2-3 structurally similar existing recipes under `recipes/` (see
   Phase 2's heuristics for picking similar recipes) to judge overlap and
   whether this app is reverse-proxy-compatible the way our recipes are.
3. Research version history: latest release, release cadence, and whether
   the project is active, in maintenance-only mode, archived, or explicitly
   EOL.
4. Evaluate fit against our current 24-recipe catalogue: does it duplicate
   something we already have, and if not, why would a customer want it?
   Note whether it has a web UI (preferred — we already have Traefik ready
   to front one) vs. requiring raw ports/protocols.
5. Evaluate installability under the CURRENT recipe mechanism constraint —
   read `apps-gaps/SCHEMA.md` for the full explanation. Summary: `/compose`
   does not accept any customer-supplied value. The only supported
   per-customer secret is a hash of the customer's own root (server)
   password, projected via either `generated_from: "<algo>:ROOT_PASSWORD"`
   on the app's own admin-login parameter, or a Traefik `basic_auth: true`
   gate in front of an app with no login of its own. Anything the app needs
   beyond that (an external API key, OAuth registration, an arbitrary
   customer-chosen credential) has no input channel today and blocks
   `installable_today`.
6. Write your findings to `apps-gaps/{{slug}}.yaml` following the schema
   documented in `apps-gaps/SCHEMA.md`.

Commit the new file only — no recipe files, no other changes.
