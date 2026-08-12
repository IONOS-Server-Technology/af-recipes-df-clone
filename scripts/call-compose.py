#!/usr/bin/env python3
"""Call af-api /compose and print the returned cloud-init to stdout."""
import argparse
import secrets
import string
import sys
from pathlib import Path

import requests
import yaml
from mtls_cert import resolve_client_cert


def random_password(length: int = 20) -> str:
    return "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(length))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipes", nargs="+", help="One or more recipe names")
    parser.add_argument("--api-url", required=True)
    parser.add_argument("--ssh-public-key", required=True)
    parser.add_argument("--root-password", default=None)
    parser.add_argument("--base-os", default="ubuntu-26.04")
    parser.add_argument(
        "--base-domain",
        default=None,
        help="Domain for Traefik HTTPS routes (e.g. an IP-derived sslip.io hostname). "
        "Omit for direct-port access, no Traefik.",
    )
    parser.add_argument(
        "--use-staging-le",
        action="store_true",
        help="Force Let's Encrypt staging instead of production for this VM's Traefik "
        "(af-api ComposeRequest.use_staging_le). Use on every CI-driven call, including "
        "against the prod cluster, whose af-api has no env-var override -- that one must "
        "stay unset so real customer VMs keep getting production certs.",
    )
    parser.add_argument(
        "--bootstrap-verification-key",
        default=None,
        help="Ed25519 public key PEM for dev-mode archive signature verification",
    )
    parser.add_argument(
        "--client-cert",
        default=None,
        help="mTLS client certificate: path to a PEM file. Supply together with "
        "--client-key on any leg that hits an af-api mTLS ingress (both real-cluster "
        "prod-mode legs); omit where no client cert is required, e.g. the ephemeral "
        "af-api of a dev-mode run.",
    )
    parser.add_argument(
        "--client-key",
        default=None,
        help="mTLS client private key: path to a PEM file. "
        "Must be supplied together with --client-cert.",
    )
    args = parser.parse_args()

    try:
        client_cert = resolve_client_cert(args.client_cert, args.client_key)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

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
            "root_password": args.root_password or random_password(),
            "ssh_public_key": args.ssh_public_key,
        },
        # "base_os": args.base_os,
    }
    if args.base_domain:
        payload["base_domain"] = args.base_domain
    if args.use_staging_le:
        payload["use_staging_le"] = True

    resp = requests.post(
        f"{args.api_url}/api/v1/compose", json=payload, timeout=30, cert=client_cert
    )
    if not resp.ok:
        print(f"/compose failed: {resp.status_code} {resp.text}", file=sys.stderr)
        return 1

    if args.bootstrap_verification_key:
        cloudinit = yaml.safe_load(resp.json()["cloud_init"])
        cloudinit["application_factory"]["dev_mode"] = True
        cloudinit["application_factory"]["bootstrap_verification_key"] = (
            args.bootstrap_verification_key
        )
        print("#cloud-config")
        print(yaml.dump(cloudinit, default_flow_style=False, allow_unicode=True), end="")
    else:
        print(resp.json()["cloud_init"], end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
