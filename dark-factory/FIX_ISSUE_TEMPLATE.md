Title: Fix schema compliance: {{name}}

This is a MECHANICAL FIX, not a research task. `apps-gaps/{{slug}}.yaml`
already contains a completed gap-analysis for "{{name}}" — do NOT
re-research the app, do NOT change any substantive finding (upstream facts,
version_health dates/cadence, catalogue_fit reasoning, the installability
verdict, or the summary's conclusions). Only fix the structural
schema-compliance problems listed below.

## Reported by `bin/validate-apps-gaps {{slug}}`

```
{{findings}}
```

## What to do

1. Read `apps-gaps/SCHEMA.md` for what each field means and the correct
   shape.
2. Open `apps-gaps/{{slug}}.yaml` and fix only the reported problem(s):
   - If it's a `secrets_expressible_today` entry with "no matching entry in
     secrets_required_at_first_boot": either add the missing name to
     `secrets_required_at_first_boot` (if the secret is real and the
     existing prose/summary already describes needing it), or remove the
     stray `secrets_expressible_today` entry (if it doesn't actually apply).
     Decide based on what the file's own `summary`/`blocking_issues` prose
     already says — don't invent a new secret that isn't otherwise
     mentioned.
   - If it's a YAML syntax error: find the actual broken line (often a
     value containing an unquoted `: ` inside a long free-text field like
     `docker_image` or a `notes` field) and quote it properly, or move the
     explanatory prose into a field meant for prose (`notes`,
     `blocking_issues`) instead of a field meant for a short value.
   - If it's a type violation (e.g. a list item that's a dict instead of a
     plain string): flatten it to a plain string, preserving the same
     information as prose within the string.
3. Run `python3 bin/validate-apps-gaps {{slug}}` and confirm it reports zero
   errors for this file before committing.

Commit only `apps-gaps/{{slug}}.yaml`. No recipe files, no other files, no
new research.

## This is enforced, not just requested

`CLAUDE.md` requires the reviewer to independently re-run
`bin/validate-apps-gaps {{slug}}` against this file before approving, and
treat any finding as blocking regardless of how the rest of the file reads —
so get it to zero errors yourself first rather than relying on rework.
Separately, `.github/workflows/validate-apps-gaps.yaml` will also run this
same check on GitHub after your commit lands on `main`, scoped to only the
file(s) you touched — a red check there afterward means something is still
wrong.
