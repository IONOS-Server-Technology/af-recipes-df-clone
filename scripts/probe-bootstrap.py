#!/usr/bin/env python3
"""POST /compose then immediately /bootstrap and dump both responses.

Diagnostic only: skips the cloud-init.yaml -> awk -> jq roundtrip we use in
the workflow so we can rule out token mangling between /compose and the
bootstrap call. If af-api can't decrypt its own freshly-issued token here,
the issue is either pod restart / replica race or a real crypto bug.
"""
from __future__ import annotations

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
    parser.add_argument("recipes", nargs="+")
    parser.add_argument("--api-url", required=True, help="af-api root, e.g. http://<host>:<port>")
    parser.add_argument("--ssh-public-key", required=True)
    parser.add_argument(
        "--bootstrap-output",
        default="bootstrap-response.tar.gz",
        help="Where to write the raw /bootstrap response body (it's a gzip'd tar, not text)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    applications = []
    for recipe in args.recipes:
        params_file = repo_root / "recipes" / recipe / "test-params.yaml"
        params = yaml.safe_load(params_file.read_text()) if params_file.exists() else {}
        applications.append({"id": recipe, "parameters": params or {}})

    compose_body = {
        "applications": applications,
        "root_credentials": {
            "root_password": random_password(),
            "ssh_public_key": args.ssh_public_key,
        },
        # "base_os": "ubuntu-26.04",
    }

    print(f"=== POST {args.api_url}/api/v1/compose ===")
    resp = requests.post(f"{args.api_url}/api/v1/compose", json=compose_body, timeout=30)
    print(f"HTTP {resp.status_code}")
    if not resp.ok:
        print(resp.text)
        return 1
    cloud_init = resp.json()["cloud_init"]
    # find the token line and capture it without awk
    token_line = next((line for line in cloud_init.splitlines() if line.strip().startswith("token:")), None)
    if token_line is None:
        print("no token line in cloud-init", file=sys.stderr)
        print(cloud_init)
        return 1
    token = token_line.split("token:", 1)[1].strip()
    segments = token.count(".") + 1
    print(f"token length={len(token)} JWE-segments={segments} (5 expected for JWE compact)")
    print(f"token[:20]={token[:20]!r}  token[-20:]={token[-20:]!r}")

    print()
    print(f"=== POST {args.api_url}/api/v1/bootstrap (body form) ===")
    boot_resp = requests.post(
        f"{args.api_url}/api/v1/bootstrap",
        json={"token": token},
        timeout=30,
    )
    print(f"HTTP {boot_resp.status_code}")
    print(f"content-type: {boot_resp.headers.get('content-type')}")
    if not boot_resp.ok:
        print("---response body---")
        print(boot_resp.text)
        print("---end---")
        return 2

    # The response is a gzip'd tar (the install archive) — not text. Printing
    # it garbles the log; write it out instead so it can be uploaded as a
    # GitHub Actions artifact and inspected locally (tar -tzvf / tar -xzf).
    out_path = Path(args.bootstrap_output)
    out_path.write_bytes(boot_resp.content)
    print(f"response body written to {out_path} ({len(boot_resp.content)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
