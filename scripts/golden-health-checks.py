#!/usr/bin/env python3
"""Verify (or regenerate) the committed golden health-check-config snapshots.

IF-1140 #7/#8. ``scripts/gen-health-check-conf.py`` is the sole definition of the
live-test suite, but nothing guarded its output against silent drift. This helper
closes that gap. It reads the golden matrix in ``tests/golden/cases.yaml`` and, for
each case, shells out to the generator:

  * default (no args) -- CHECK mode. Runs the generator with ``--check <golden>``
    per case, so the generator diffs its fresh output against the committed golden.
    Any drift is reported on a single actionable ``::error::`` line and the helper
    exits non-zero once every case has been tried; exit 0 only if all match.

  * ``--update`` -- runs the generator with ``--update <golden>`` per case, writing
    (or rewriting) every committed golden from the current generator output.

This helper is the source of truth invoked BOTH by CI (the detect-changed-recipes
job runs ``python3 scripts/golden-health-checks.py``) and by humans regenerating the
goldens (``python3 scripts/golden-health-checks.py --update``). It stays
dependency-light: stdlib plus the PyYAML the rest of the repo already uses.
"""

import argparse
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
GENERATOR = REPO_ROOT / "scripts" / "gen-health-check-conf.py"
CASES_FILE = REPO_ROOT / "tests" / "golden" / "cases.yaml"

REQUIRED_FIELDS = ("name", "recipes", "base_domain", "recipe_label", "golden")


def load_cases() -> list[dict]:
    """Read and lightly validate the golden matrix."""
    doc = yaml.safe_load(CASES_FILE.read_text())
    cases = doc.get("cases") if isinstance(doc, dict) else None
    if not cases:
        sys.exit(f"::error::{CASES_FILE} has no 'cases' list")
    for case in cases:
        missing = [f for f in REQUIRED_FIELDS if f not in case]
        if missing:
            sys.exit(
                f"::error::case {case.get('name', '<unnamed>')} in {CASES_FILE} "
                f"is missing required field(s): {', '.join(missing)}"
            )
    return cases


def generator_args(case: dict) -> list[str]:
    """Translate a case's fields into gen-health-check-conf.py CLI arguments."""
    args = list(case["recipes"])
    args += ["--base-domain", str(case["base_domain"])]
    args += ["--recipe-label", str(case["recipe_label"])]
    if case.get("le_staging"):
        args.append("--expect-le-staging")
    return args


def run_case(case: dict, mode_flag: str) -> subprocess.CompletedProcess:
    """Invoke the generator for one case in --check or --update mode."""
    golden = (REPO_ROOT / case["golden"]).resolve()
    cmd = [
        sys.executable,
        str(GENERATOR),
        *generator_args(case),
        mode_flag,
        str(golden),
    ]
    return subprocess.run(cmd, capture_output=True, text=True)


def do_update(cases: list[dict]) -> int:
    for case in cases:
        result = run_case(case, "--update")
        if result.returncode != 0:
            print(result.stdout, end="")
            print(result.stderr, end="", file=sys.stderr)
            print(
                f"::error::failed to regenerate golden for case "
                f"{case['name']} ({case['golden']})"
            )
            return 1
        print(f"updated {case['golden']} ({case['name']})")
    return 0


def do_check(cases: list[dict]) -> int:
    failures = []
    for case in cases:
        result = run_case(case, "--check")
        if result.returncode == 0:
            print(f"ok    {case['name']} ({case['golden']})")
            continue
        failures.append(case["name"])
        # Surface the generator's unified diff so the drift is visible in logs.
        print(result.stdout, end="")
        print(result.stderr, end="", file=sys.stderr)
        print(
            f"::error::golden drift in case {case['name']}: generated config "
            f"differs from {case['golden']}. Regenerate with "
            f"'python3 scripts/golden-health-checks.py --update' and commit."
        )
    if failures:
        print(
            f"\n{len(failures)} of {len(cases)} golden case(s) drifted: "
            f"{', '.join(failures)}",
            file=sys.stderr,
        )
        return 1
    print(f"\nall {len(cases)} golden case(s) match")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--update",
        action="store_true",
        help="regenerate every committed golden from the current generator output "
        "instead of checking against them",
    )
    args = parser.parse_args()

    cases = load_cases()
    return do_update(cases) if args.update else do_check(cases)


if __name__ == "__main__":
    sys.exit(main())
