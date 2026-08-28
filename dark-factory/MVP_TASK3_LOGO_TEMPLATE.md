Title: AF recipe logo: {{name}} ({{slug}})

Find, normalize, verify, and install a logo for "{{name}}" using the
`af-recipe-logo` skill — task 3 of the MVP build-now pipeline (merged from
the earlier 3a/3b split: no human review gate on individual logos anymore —
`enabled: false` is the real safety net until a human flips it, so this
task runs end-to-end in one pass).

**Depends on task 1**: `recipes/{{slug}}/metadata.yaml` must already exist
with a `recipe_version` field set — `apply.py` (step 7 below) requires it
to bump. This issue should be dispatched with `requires: [<task 1's issue
id>]` so dark-factory doesn't claim it before task 1 has actually landed
— finding/normalizing/verifying (steps 1-6) don't need task 1's output,
only the final apply step does, but there's no way to split that
mid-task, so the whole issue waits. If this task somehow still ran before
`metadata.yaml` exists, stop and report instead of proceeding — don't
guess at a `recipe_version` to bump from.

## What to do

1. Read `.claude/skills/af-recipe-logo/SKILL.md` in full — steps 1-4
   (Find, Normalize, Verify, Install) are this task's actual method. What
   follows here is only what's specific to running it as a dark-factory
   issue rather than interactively.

2. **Bootstrap dependencies.** `node`/`npm` are already present in this
   worker image; Python `Pillow` is not (and can't be `pip install`ed
   directly — externally-managed-environment). Use the venv bootstrap from
   `CLAUDE.md`, adapted for Pillow, then put it first on `PATH` so the
   skill's own `python3` invocations pick it up automatically:
   ```bash
   python3 -m venv --without-pip /tmp/v
   curl -sSL https://bootstrap.pypa.io/get-pip.py | /tmp/v/bin/python3
   /tmp/v/bin/pip install -q Pillow
   export PATH="/tmp/v/bin:$PATH"
   bash .claude/skills/af-recipe-logo/scripts/ensure_deps.sh
   ```
   This vendored copy of the skill does **not** use the `gh` CLI or any
   `GH_TOKEN` — `find_source.py`'s GitHub lookups are plain unauthenticated
   `https://api.github.com` calls, capped at 60 req/hour. That's expected
   and fine for one recipe; don't try to work around the rate limit.

3. **Derive both `--website` and `--repo` from `apps-gaps/{{slug}}.yaml`'s
   `upstream` section:**
   - `--website <upstream.url>` — pass this whenever `upstream.url` isn't
     itself a GitHub URL. **Try this first, it's usually the better
     source**: a project's own favicon is purpose-built square and legible,
     while its repo's `logo.svg` is often a wordmark, or uses a
     semi-transparent-layer trick that assumes a white page and degrades on
     a dark tile (found researching this pipeline — `verify.py` did not
     catch it, only actually rendering the tile did).
   - `--repo <owner>/<repo>`, derived from `upstream.repo_url` if it's a
     `github.com/<owner>/<repo>` URL.
   If neither resolves to anything usable, omit them — the dashboardicons
   waterfall stages still run without either, just report which stages got
   skipped and why.

4. Run `python3 .claude/skills/af-recipe-logo/scripts/find_source.py {{slug}}
   --website <url> --repo <owner>/<repo>` from the `af-recipes-clone` root
   (omit either flag per step 3 if it doesn't apply). Its recommendation is
   a suggestion, not a decision — sanity check the chosen URL is plausibly
   "{{name}}"'s own mark before using it (not a generic UI glyph mistaken
   for the brand mark — a repeated false-positive class in this pipeline),
   and prefer an icon-only mark over a wordmark/lockup if multiple
   candidates are usable.

5. Normalize the chosen candidate:
   `python3 .claude/skills/af-recipe-logo/scripts/normalize.py <url-or-path>
   /tmp/{{slug}}.svg --tile /tmp/{{slug}}-tile.png`. If the fidelity RMSE
   the script reports is above 8, look closely at the tile before
   proceeding — the artwork may have changed shape.

   **Don't reflexively drop a background layer.** A real bug found on
   `kaneo`: its real favicon is a deliberate two-layer design (a solid dark
   plate + a near-white mark on top, the same "brand ships its mark as a
   filled tile" pattern `SKILL.md` documents for Portainer) — normalizing
   it down to just the light foreground path left a near-invisible pale
   shape on transparent, illegible on any light background. Only use
   `--strip-bg` when the background is genuinely an *added* plate (e.g. a
   generic white/checkerboard matte around the real mark), not when it's
   part of the brand's own design — check by rendering the tile with and
   without the background before deciding, don't assume either way. Use
   `--keep-parts` instead of `--strip-bg` only if the source is a lockup
   (symbol + wordmark) and the symbol alone is
   usable — see the skill's "Splitting a symbol out of a lockup" section.

6. Verify: `python3 .claude/skills/af-recipe-logo/scripts/verify.py
   /tmp/{{slug}}.svg`. Read the skill's "acceptable after a look at the
   tile" vs. "never acceptable" lists before judging any WARN/ERROR
   yourself — don't just report the raw output. **`verify.py` passing
   clean is not sufficient on its own** — it has known blind spots (opacity
   layers that vanish on a dark composite, a cutout mark that reads as
   nothing once rendered). Actually look at the rendered tile yourself
   (it's a PNG — read it) before deciding the mark is legible and correct,
   not just that the mechanical checks passed.

7. Install it:
   ```bash
   python3 .claude/skills/af-recipe-logo/scripts/apply.py {{slug}} \
     /tmp/{{slug}}.svg --source '<the exact asset URL from step 4>' \
     --license trademark-nominative-fair-use --bump minor --dry-run
   ```
   Check the printed diff (old → new `recipe_version`, `logo_sha256`,
   `logo_url`), then re-run the identical command **without** `--dry-run`
   to actually write `logo.svg` and update `metadata.yaml`. If step 6's own
   look at the tile found the mark illegible, off-brand, or otherwise not
   good enough — don't run `apply.py` at all. Report "no usable logo found"
   per `SKILL.md`'s documented shape instead of forcing a bad candidate
   through; that's a complete, valid outcome for this task, not a failure.

8. **Self-check against RFC-002's logo rules** (`rfc/002-recipe-rules.md`
   §3.3) — square viewBox, safe area, transparent background, no embedded
   script, no animation, sha256 matches the file. There's no local copy of
   `af-api`'s validator to cross-check against (`af-api` is a separate,
   private repo this project's worker has no credentials for) — this
   manual pass against the RFC doc is the check available here; task 4
   (`af-validate`) is the independent second opinion, not this task's job.

9. Commit `recipes/{{slug}}/logo.svg` and `recipes/{{slug}}/metadata.yaml`
   together — no other files. Push normally; there's no PR to open
   (dark-factory has no PR concept — a verified push to `main` is what
   "done" means here). `enabled: false` keeps this non-customer-visible
   regardless of when it lands.

10. **Attach the tile to this issue** even though a human isn't gating on
    it anymore — it's still useful record-keeping for a later spot-check:
    ```bash
    curl -sS -X POST -H "Authorization: Bearer ${FACTORY_API_TOKEN}" \
      -F "file=@/tmp/{{slug}}-tile.png" \
      "${FACTORY_API_URL:-http://127.0.0.1:30080}/v1/issues/${QUEUE_ISSUE_ID}/attachments"
    ```

## Report back — always, even if nothing was written

State explicitly: where the artwork came from (exact asset URL, not the
project homepage), which waterfall stage, vector or wrapped raster (+
pixel size if raster), what normalization changed, every verify finding
(including ones judged acceptable) and confirmation you actually looked at
the rendered tile rather than trusting `verify.py` alone, **explicitly flag
a borrowed mark** if the artwork belongs to a different project than the
recipe, the `recipe_version` bump (old → new), `logo_sha256`, `logo_url`,
and confirmation the tile is attached. If no usable/legible source was
found, report that plainly (what was searched, what came back empty or
was rejected and why) rather than forcing a bad candidate through.

## This is enforced, not just requested

The `af-validate-rfc002` CI job runs the real `af-validate` CLI (the full
RFC-002 rule set, including the logo rules) against this file once it's
part of a PR — step 8's self-check catches the same class of problem
early, it doesn't replace that gate.
