---
name: af-update-recipes
description: Sweep the recipe catalogue against RFC-002 and surface every violation, with a draft fix for each. Use when an RFC-002 rule has been added, changed, or removed, or when the developer wants a snapshot audit of how the catalogue stands relative to the current spec. The skill iterates every `recipes/<slug>/` against the rules in `rfc/002-recipe-rules.md`, drafts a per-recipe patch for each ERROR finding, and hands the developer one branch and PR per affected recipe to review and ship. TRIGGER when the user wants to "update all recipes after a rule change", "sweep recipes for RFC-002 violations", "check the catalogue against the spec", "af-update-recipes", or references a maintenance pass on af-recipes. SKIP for: bootstrapping a single new recipe (use af-create-recipe), editing one specific recipe by hand, or applying mechanical batch transformations unrelated to RFC-002.
---

# Sweep the recipe catalogue against RFC-002

The other half of WP4 alongside `af-create-recipe`: where that skill helps create one new recipe, this one keeps the existing 22 recipes aligned with RFC-002 as the spec evolves. The developer drives; the skill scans, drafts, and hands back per-recipe diffs. The developer reviews, commits, and ships.

## Operating mode

- Run from inside a clone of `af-recipes`. The CWD must be the repo root (where `recipes/` and `rfc/` live). If the bash command in Phase 1 fails because those paths don't exist, stop and tell the developer to `cd` into the af-recipes clone before re-triggering.
- This skill **never** commits, pushes, or opens PRs on its own. It produces patches and per-recipe handover blurbs. The developer ships them.
- The skill does not depend on `af-validate` or any external CLI — RFC-002 is the canonical rule list and is applied by the agent. If `af-validate` is also installed, the developer can cross-check independently.

## Phase 1 — Intake (silent if the trigger is complete)

Parse the trigger for: which rules to sweep against. Patterns:

- *No filter* (`/af-update-recipes`): sweep against **every rule** in RFC-002. Useful for periodic audits or first-time spec adoption.
- *Single rule* (`/af-update-recipes no-public-db-port`): sweep only that rule. Useful immediately after a rule has been added or changed — much shorter output.
- *Diff against a ref* (`/af-update-recipes --since main`): sweep against rules that changed in `rfc/002-recipe-rules.md` between `main` and the current branch (or whatever ref the developer names). Useful when reviewing a PR that introduces or modifies rules.

Then, in this order:

1. **CWD check.** If `recipes/` or `rfc/` are not visible from the current directory, stop and tell the developer to `cd` into the af-recipes clone before re-triggering.
2. **Branch state.** Run `git status` — if there are uncommitted changes, ask the developer whether to proceed (the per-recipe patches will be written into the working tree; mixing them with unrelated edits is messy).
3. **Missing-info check.** If the trigger uses `--since` but no ref is given, ask once.

If 1–3 all pass and nothing is missing, **do not ask the developer anything else** — proceed straight to Phase 2.

## Phase 2 — Sweep

Read [`rfc/002-recipe-rules.md`](../../../rfc/002-recipe-rules.md) and resolve the rule set to apply (full list, single rule, or diff). For each `recipes/<slug>/`:

- Apply every rule in scope, in the order RFC-002 declares them.
- Collect findings as `(slug, rule-slug, level, message)` tuples.

Cross-recipe rules (`no-duplicate-public-port`, `incompatibility-ref-valid`) run once across the catalogue, not per recipe.

Output a compact table grouped by recipe:

```
adguard-home
  service-has-healthcheck         ⚠ WARN — service 'adguard' has no healthcheck

gitea
  bind-mount-under-opt            ⚠ WARN — '/var/data' should be under /opt/gitea/

n8n
  ✓ no findings

vaultwarden
  no-public-db-port               ✗ ERROR — service 'db' exposes 5432
  service-has-healthcheck         ⚠ WARN — service 'db' has no healthcheck
```

Cross-recipe findings appear in their own block at the end. WARN findings are reported but do not by themselves cause a per-recipe fix branch — only ERROR findings do.

Wait for developer confirmation before generating fix patches (they may want to address findings manually, or accept WARNs without fixing).

## Phase 3 — Plan per affected recipe

For every recipe with at least one ERROR finding, draft a one-screen plan:

- The findings to fix
- What the patch will change (specific files, specific lines or sections)
- Open questions ("the host port collides with `pihole` — do we change `vaultwarden` to a free port, or add to `incompatible_with_apps`?")

Wait for the developer to OK or adjust before writing files.

## Phase 4 — Generate patches + Self-Check

For each recipe with ERROR findings, in turn:

1. Create a fix branch name suggestion: `fix/IF-<ticket>-<slug>-rfc002-sweep` (ask for the ticket once, reuse for all)
2. Write the patches into `recipes/<slug>/`
3. Re-walk RFC-002 against the patched recipe; the relevant ERROR findings should now be ✓. Cross-recipe rules also re-run.
4. Output per recipe:

```
recipes/vaultwarden/  (3 errors → 0)
  no-public-db-port               ✓ (was ✗)  removed host port mapping for db service
  service-has-healthcheck         (still ⚠ WARN, not addressed by this sweep)
```

If a fix introduces a new ERROR (e.g. resolving one rule violates another), surface it to the developer rather than silently iterating — the developer decides.

## Phase 5 — Per-recipe handover

For each fixed recipe, present:

1. **Diff:** `git diff` against `recipes/<slug>/`
2. **Suggested branch name:** `fix/IF-<ticket>-<slug>-rfc002-sweep`
3. **Suggested commit message** — one line subject naming the rule fixed, optional body listing the specific changes
4. **`gh pr create` body** linking the JIRA ticket, the rule slug(s) being addressed, and a brief description

The skill stops there. The developer reviews each diff, commits, pushes, opens the PR. The skill does not produce one giant PR across all recipes — every recipe is its own PR so reviewers can approve independently.

## What this skill does NOT do

- Auto-commit, auto-push, auto-PR — every shipping action stays with the developer (same principle as `af-create-recipe`)
- Modify `rfc/002-recipe-rules.md` itself — RFC-002 is human-authored; this skill only enforces it on the catalogue
- Fix WARN findings unless explicitly asked — WARN is advisory, the developer decides per-recipe whether the warning is worth a fix
- Resolve genuinely ambiguous cases automatically — when a rule violation has multiple valid fixes, the skill asks the developer rather than picking

## References

- [`rfc/002-recipe-rules.md`](../../../rfc/002-recipe-rules.md) — the rules this skill enforces (canonical)
- `.claude/skills/af-create-recipe/references/recipe-anatomy.md` — annotated recipe walkthrough; useful when drafting fixes that touch unfamiliar files
- `recipes/<any>/` — read 2-3 clean recipes for structural reference when a fix is non-obvious

## Bash hook caveat

This developer's environment blocks Bash command chaining with `&&` or `;`. Make tool calls separately rather than chaining. This is unrelated to the recipe content; it's a workflow constraint.
