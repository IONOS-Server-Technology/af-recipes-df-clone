#!/usr/bin/env python3
"""Pick recipe combinations for the CI install-test matrix.

Reads the static catalogue.json in the repo root and prints a compact JSON list
of objects to stdout, ready to be spliced into a GitHub Actions
`strategy.matrix.include`. Every value is a scalar because Actions cannot
expand a list inside a matrix entry:

    [{"apps":"immich n8n","label":"immich+n8n","size":2}]

`apps` is meant to be passed straight to `call-compose.py`, `label` is meant
for the job name. Diagnostics (pool, effective seed, resource sums) go to
stderr so stdout stays pure JSON.

Examples:
    scripts/select-combinations.py --sizes 1,2,3 --seed 42
    scripts/select-combinations.py --fixed-combos "immich+n8n,vaultwarden"
    scripts/select-combinations.py --sizes 1,2,3 --seed 42 --compose-only
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path
from typing import Any, NamedTuple

# Members of one combination are joined with "+", combinations are separated
# by ",". Same grammar for --fixed-combos input and for the emitted `label`,
# so a label copied out of a failed CI job can be pasted back in verbatim.
MEMBER_SEPARATOR = "+"
COMBO_SEPARATOR = ","

# RAM the OS itself needs; the declared per-app minima sit on top of it.
OS_BASELINE_RAM_MB = 768

# A redraw budget, not a filter: it only kicks in when the requested sizes can
# collide (e.g. --sizes 1,1), and never removes a combination from the pool.
MAX_DRAW_ATTEMPTS = 20


class Combination(NamedTuple):
    members: tuple[str, ...]

    @property
    def label(self) -> str:
        return MEMBER_SEPARATOR.join(self.members)

    def as_matrix_entry(self) -> dict[str, Any]:
        return {"apps": " ".join(self.members), "label": self.label, "size": len(self.members)}


def load_recipes(catalogue_path: Path) -> dict[str, dict[str, Any]]:
    """Return every catalogue entry keyed by recipe id.

    Note the static catalogue.json is *not* shaped like the af-api /catalogue
    response: the top-level key is `recipes` and the resource minima are flat
    `app_min_*_mb` keys rather than a nested `resources` object.
    """
    data = json.loads(catalogue_path.read_text())
    return {entry["id"]: entry for entry in data["recipes"]}


def is_eligible(entry: dict[str, Any]) -> bool:
    """Installable on its own: shipped to customers and not pulled in implicitly.

    docker_auto_inject recipes (e.g. wud) are added by af-api behind the scenes
    whenever a docker-compose app is selected, so testing them as a standalone
    selection tests nothing.
    """
    return bool(entry.get("enabled")) and not bool(entry.get("docker_auto_inject"))


def is_docker_compose(entry: dict[str, Any]) -> bool:
    """Whether af-api installs this recipe by running docker compose.

    Deliberately kept out of is_eligible(): eligibility is a property of the
    recipe itself, while "must be docker-compose" is a property of one CI leg.
    The docker leg runs every app through `docker compose -f
    recipes/<id>/docker-compose.yaml`, which a `recipe_type: native` recipe has
    no file for; the live VM leg installs natives perfectly well and must keep
    covering them. Hence --compose-only rather than a wider eligibility rule.
    """
    return entry.get("recipe_type") == "docker-compose"


def parse_sizes(raw: str) -> list[int]:
    sizes = []
    for chunk in raw.split(COMBO_SEPARATOR):
        chunk = chunk.strip()
        if not chunk:
            continue
        try:
            sizes.append(int(chunk))
        except ValueError:
            raise ValueError(f"--sizes must be comma-separated integers, got {chunk!r}") from None
    if not sizes:
        raise ValueError("--sizes did not contain any size")
    return sizes


def parse_fixed_combos(
    raw: str, recipes: dict[str, dict[str, Any]], compose_only: bool
) -> list[Combination]:
    """Parse "a+b,c" into combinations, rejecting anything not installable.

    Fixed combinations never touch the pool, so every restriction the pool
    applies has to be repeated here.
    """
    combos = []
    for chunk in raw.split(COMBO_SEPARATOR):
        chunk = chunk.strip()
        if not chunk:
            continue
        members = [member.strip() for member in chunk.split(MEMBER_SEPARATOR) if member.strip()]
        if not members:
            raise ValueError(f"empty combination in --fixed-combos: {chunk!r}")
        if len(set(members)) != len(members):
            raise ValueError(f"duplicate recipe id in --fixed-combos combination {chunk!r}")
        for member in members:
            entry = recipes.get(member)
            if entry is None:
                raise ValueError(f"unknown recipe id in --fixed-combos: {member!r}")
            # Checked before `enabled`: a native recipe can never run on the
            # docker leg, whereas being disabled is a transient state.
            if compose_only and not is_docker_compose(entry):
                raise ValueError(
                    "recipe is not a docker-compose recipe and cannot run on the "
                    f"docker leg: {member!r}"
                )
            if not entry.get("enabled"):
                raise ValueError(f"recipe is disabled and cannot be installed: {member!r}")
            if entry.get("docker_auto_inject"):
                raise ValueError(
                    f"recipe is docker_auto_inject and cannot be selected directly: {member!r}"
                )
        combos.append(Combination(tuple(sorted(members))))
    if not combos:
        raise ValueError("--fixed-combos did not contain any combination")
    return combos


def draw_combos(sizes: list[int], pool: list[str], rng: random.Random) -> list[Combination]:
    combos: list[Combination] = []
    seen: set[frozenset[str]] = set()
    for size in sizes:
        for _ in range(MAX_DRAW_ATTEMPTS):
            # Members are sorted so the label — and therefore the CI job name —
            # does not depend on the order rng.sample happened to return.
            candidate = Combination(tuple(sorted(rng.sample(pool, size))))
            if frozenset(candidate.members) not in seen:
                combos.append(candidate)
                seen.add(frozenset(candidate.members))
                break
        else:
            print(
                f"size {size}: no combination left that is not already selected, skipping",
                file=sys.stderr,
            )
    return combos


def log_resources(combo: Combination, recipes: dict[str, dict[str, Any]]) -> None:
    """Report the declared minima for information only.

    Deliberately NOT a fit check: nothing in af-api enforces these numbers, and
    open-webui declares 8192 MB RAM yet installs fine on the 8 GB test VM, so
    they are advisory at best. Capping draws by a "fits the VM" rule would also
    collapse the 3-app draw to almost a single possible combination, which
    defeats the point of randomising. Do not turn this into a filter.
    """
    ram = OS_BASELINE_RAM_MB + sum(recipes[member]["app_min_ram_mb"] for member in combo.members)
    disk = sum(recipes[member]["app_min_disk_mb"] for member in combo.members)
    print(
        f"  {combo.label}: declared minima ~{ram} MB RAM "
        f"({OS_BASELINE_RAM_MB} MB OS baseline + apps), ~{disk} MB disk (informational only)",
        file=sys.stderr,
    )


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--sizes",
        default="1,2,3",
        help="Comma-separated combination sizes; one combination is drawn per size "
        "(default: %(default)s)",
    )
    parser.add_argument(
        "--fixed-combos",
        default=None,
        help='Use explicit combinations instead of drawing, e.g. "immich+n8n,vaultwarden": '
        "members joined by '+', combinations separated by ',' — the same format as the "
        "emitted `label`. Ignores --sizes and --seed.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Integer seed for the draw. The same seed always yields byte-identical "
        "stdout. Omit to seed from system entropy; the effective seed is logged to "
        "stderr either way so a CI run can be replayed.",
    )
    parser.add_argument(
        "--compose-only",
        action="store_true",
        help="Restrict the selection to `recipe_type: docker-compose` recipes. Meant for "
        "the docker CI leg, which brings every app up with `docker compose` and so cannot "
        "install a native recipe; the live VM leg installs natives and must not pass this.",
    )
    parser.add_argument(
        "--catalogue",
        type=Path,
        default=repo_root / "catalogue.json",
        help="Path to the static catalogue.json (default: %(default)s)",
    )
    args = parser.parse_args()

    if not args.catalogue.is_file():
        print(f"catalogue not found: {args.catalogue}", file=sys.stderr)
        return 1
    try:
        recipes = load_recipes(args.catalogue)
    except (KeyError, TypeError, ValueError) as exc:
        print(f"could not read catalogue {args.catalogue}: {exc}", file=sys.stderr)
        return 1

    # --compose-only narrows the pool rather than the drawn combinations: a
    # discarded combination would silently shrink the matrix, and the
    # `size > len(pool)` guard below has to count what can actually be drawn.
    pool = sorted(
        recipe_id
        for recipe_id, entry in recipes.items()
        if is_eligible(entry) and (not args.compose_only or is_docker_compose(entry))
    )
    # Name the restriction in both diagnostics so a CI log explains a pool that
    # is smaller than the catalogue would suggest.
    scope = " docker-compose" if args.compose_only else ""
    if not pool:
        print(f"no enabled, non-auto-inject{scope} recipes in {args.catalogue}", file=sys.stderr)
        return 1
    print(f"eligible{scope} pool ({len(pool)}): {' '.join(pool)}", file=sys.stderr)

    if args.fixed_combos:
        try:
            combos = parse_fixed_combos(args.fixed_combos, recipes, args.compose_only)
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1
    else:
        try:
            sizes = parse_sizes(args.sizes)
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        for size in sizes:
            if size < 1:
                print(f"size must be >= 1, got {size}", file=sys.stderr)
                return 1
            if size > len(pool):
                print(
                    f"size {size} exceeds the eligible pool of {len(pool)} recipes",
                    file=sys.stderr,
                )
                return 1
        # A Random instance, never the module-level functions: the global RNG is
        # shared state that anything else in the process could reseed, and the
        # seed must be the only input to the draw.
        seed = args.seed if args.seed is not None else random.SystemRandom().randrange(2**32)
        print(f"seed: {seed}, sizes: {sizes}", file=sys.stderr)
        combos = draw_combos(sizes, pool, random.Random(seed))

    deduped: list[Combination] = []
    seen: set[frozenset[str]] = set()
    for combo in combos:
        key = frozenset(combo.members)
        if key in seen:
            print(f"dropping duplicate combination: {combo.label}", file=sys.stderr)
            continue
        seen.add(key)
        deduped.append(combo)

    if not deduped:
        print("no combinations selected", file=sys.stderr)
        return 1

    print(f"selected {len(deduped)} combination(s):", file=sys.stderr)
    for combo in deduped:
        try:
            log_resources(combo, recipes)
        except KeyError as exc:
            # Advisory numbers, so a broken catalogue must not take the draw with
            # it — and a KeyError traceback out of here would misattribute a
            # catalogue problem to the selector. Warn and carry on instead.
            print(
                f"could not compute declared minima for {combo.label}: missing {exc}",
                file=sys.stderr,
            )

    print(json.dumps([combo.as_matrix_entry() for combo in deduped], separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
