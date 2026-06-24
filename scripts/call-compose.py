#!/usr/bin/env python3
"""Call af-api /compose and print the returned cloud-init to stdout."""
import argparse
import secrets
import string
import sys
from pathlib import Path

import requests
import yaml


def random_password(length: int = 20) -> str:
    return "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(length))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipes", nargs="+", help="One or more recipe names")
    parser.add_argument("--api-url", required=True)
    parser.add_argument("--ssh-public-key", required=True)
    parser.add_argument("--root-password", default=None)
    parser.add_argument("--base-os", default="ubuntu-26.04")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    applications = []
    for recipe in args.recipes:
        recipe_dir = repo_root / "recipes" / recipe
        if not recipe_dir.is_dir():
            print(f"recipe directory not found: {recipe_dir}", file=sys.stderr)
            return 1
        params_file = recipe_dir / "test-params.yaml"
        params = yaml.safe_load(params_file.read_text()) if params_file.exists() else {}
        applications.append({"id": recipe, "parameters": params or {}})

    payload = {
        "applications": applications,
        "root_credentials": {
            "root_credentials": args.root_password or random_password(),
            "ssh_public_key": args.ssh_public_key,
        },
        # "base_os": args.base_os,
    }

    resp = requests.post(f"{args.api_url}/api/v1/compose", json=payload, timeout=30)
    if not resp.ok:
        print(f"/compose failed: {resp.status_code} {resp.text}", file=sys.stderr)
        return 1

    print(resp.json()["cloud_init"], end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
