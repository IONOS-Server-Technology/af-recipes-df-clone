Title: Re-check recommendation: {{name}}

`CLAUDE.md` was just corrected: `installability.recommendation` must be
driven ONLY by installability/mechanism (`installable_today`, what secrets
a mechanism exists for, upstream health) — never by catalogue overlap with
another recipe/candidate, and never by a subjective audience-size/niche
judgment. `apps-gaps/{{slug}}.yaml` was analyzed before that correction and
its current recommendation may have been downgraded on exactly those now-
disallowed grounds.

{{fork_hint}}
## What to do

1. Read the "Overlapping/competing apps in the catalogue are fine" section
   of `CLAUDE.md` for the corrected rule.
2. Open `apps-gaps/{{slug}}.yaml` yourself and look at ONLY
   `installability.installable_today` and `installability.blocking_issues`
   as currently written (the `summary` field may also reference the
   now-disallowed grounds — treat it the same way in step 4). Do not
   re-research upstream facts, version_health, or re-derive
   catalogue_fit.overlaps_with/differentiation — those stay as they are;
   overlap/audience-size descriptions there are fine, they're description,
   not a recommendation input.
3. Re-derive `installability.recommendation` from those two fields alone,
   per the corrected rule:
   - `installable_today: true` and `blocking_issues: []` → `build_now`.
   - `installable_today: true` with a real, non-overlap, non-audience-size
     blocking issue (e.g. a genuine functional caveat, a licensing cap, a
     degraded secondary feature) → `build_with_caveats`, and the caveat
     named in `blocking_issues`/`summary` must be that real issue, not
     overlap or niche framing.
   - `installable_today: false` → `blocked_on_platform` or
     `not_recommended` as already documented in `apps-gaps/SCHEMA.md`
     (unchanged by this correction).
4. If the recommendation changes, rewrite `summary`'s last 1-2 sentences to
   match the new verdict and drop any overlap/audience-size justification
   for *why* it's build_with_caveats rather than build_now. Overlap can
   still be mentioned as fact (e.g. "overlaps with X") — just not as the
   reason for the caveat.
5. Run `python3 bin/validate-apps-gaps {{slug}}` (see `CLAUDE.md` for the
   pyyaml/jsonschema bootstrap if needed) and confirm zero errors before
   committing.

Commit only `apps-gaps/{{slug}}.yaml`. No recipe files, no other files, no
new research.
