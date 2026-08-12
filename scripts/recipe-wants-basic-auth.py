#!/usr/bin/env python3
"""Print "true"/"false": does this recipe get a Traefik basicauth middleware? (IF-1458)

Mirrors af-api's ``Recipe.wants_basic_auth`` (af_api/core/models.py) so the live test
can assert the right expectation per recipe. Kept deliberately as a parse of
metadata.yaml rather than a grep: ``basic_auth`` appears in prose comments in
recipes that do *not* enable it (vaultwarden's ADMIN_TOKEN note is the live
example), and a grep would classify those as protected and then fail the
"unprotected app must not answer 401" assertion in the wrong direction.

The upstream semantics being mirrored:
  wants_basic_auth = any(p.basic_auth for p in ports if p.traefik_routed)
  traefik_routed   = p.public and p.http and p.protocol == "tcp"
with defaults http=True and basic_auth=False. Auth applies to the whole router,
so any routed port opting in protects the app.

This duplicates a rule that lives in af-api, so it can drift. Nothing enforces the
parity automatically (af-api is a separate repo and is not importable here). The
drift is self-announcing in the direction that matters, though: if af-api starts
protecting a recipe this still calls unprotected, the live test fails on the
"unprotected app must not answer 401" assertion rather than passing quietly.
"""
import argparse
import sys
from pathlib import Path

import yaml


def wants_basic_auth(metadata: dict) -> bool:
    for port in metadata.get("ports") or []:
        traefik_routed = (
            bool(port.get("public"))
            and bool(port.get("http", True))
            and port.get("protocol") == "tcp"
        )
        if traefik_routed and bool(port.get("basic_auth", False)):
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipe", help="Recipe name, i.e. the directory under recipes/")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    metadata_file = repo_root / "recipes" / args.recipe / "metadata.yaml"
    if not metadata_file.is_file():
        print(f"metadata.yaml not found for recipe '{args.recipe}': {metadata_file}", file=sys.stderr)
        return 1

    metadata = yaml.safe_load(metadata_file.read_text()) or {}
    print("true" if wants_basic_auth(metadata) else "false")
    return 0


if __name__ == "__main__":
    sys.exit(main())
