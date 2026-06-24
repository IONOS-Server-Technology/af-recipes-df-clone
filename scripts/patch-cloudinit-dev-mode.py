#!/usr/bin/env python3
"""Patch the cloud-init returned by /compose so the live test can reach af-api.

The live test deploys af-api behind a plain-HTTP NodePort Service (no TLS), so
the VM has to talk to the bootstrap endpoint over ``http://``. The
``cc_application_factory`` cloud-init module rejects an ``http://`` bootstrap_url
with a non-loopback host unless dev mode is active (see af-cloud-init's
``_validate_config``). This helper rewrites the ``application_factory`` block of
the /compose output to:

  * ``dev_mode: true``  — activates the module's debug/dev mode (which, paired
    with the image-side ``/etc/app-factory/.dev-mode-enabled`` sentinel that the
    test image is built with, relaxes the TLS/HTTP restrictions), and
  * rewrite ``bootstrap_url`` from ``https://`` to ``http://`` so the VM hits the
    af-api NodePort directly.

It is a CI-only transform — production cloud-init must never carry ``dev_mode``.
"""
from __future__ import annotations

import argparse
import sys
import urllib.parse
from pathlib import Path

import yaml

CLOUD_CONFIG_HEADER = "#cloud-config"


def patch_cloud_init(text: str) -> str:
    """Return *text* with the application_factory block patched for dev/HTTP.

    Raises ValueError if the document has no ``application_factory`` block or no
    ``bootstrap_url`` inside it — that would mean /compose returned something we
    do not understand and silently shipping it unpatched would mask the problem.
    """
    doc = yaml.safe_load(text)
    if not isinstance(doc, dict):
        raise ValueError("cloud-init is not a YAML mapping")

    af_cfg = doc.get("application_factory")
    if not isinstance(af_cfg, dict):
        raise ValueError("cloud-init has no 'application_factory' mapping")

    af_cfg["dev_mode"] = True

    bootstrap_url = af_cfg.get("bootstrap_url")
    if not bootstrap_url:
        raise ValueError("application_factory block has no 'bootstrap_url'")

    if af_cfg["bootstrap_url"].startswith('https'):
        af_cfg["bootstrap_url"] = af_cfg["bootstrap_url"].replace('https', 'http', 1)


    # write_files:
    # - content: |
    #     15 * * * * root ship_logs
    #   path: /etc/crontab
    #   append: true
    doc["write_files"] = [{"content": "", "path": "/etc/app-factory/.dev-mode-enabled", "append": True}]

    # safe_dump drops the leading '#cloud-config' comment that cloud-init
    # requires, so re-prepend it. width is set high so the long JWE token in
    # the block is never wrapped. sort_keys=False keeps /compose's key order.
    body = yaml.safe_dump(doc, sort_keys=False, allow_unicode=True)
    return f"{CLOUD_CONFIG_HEADER}\n{body}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "cloudinit",
        help="Path to the cloud-init YAML from /compose, or '-' to read stdin",
    )
    args = parser.parse_args()


    text = Path(args.cloudinit).read_text()

    try:
        patched = patch_cloud_init(text)
    except (ValueError, yaml.YAMLError) as exc:
        print(f"failed to patch cloud-init: {exc}", file=sys.stderr)
        return 1

    Path(args.cloudinit).write_text(patched)
    af = yaml.safe_load(patched)["application_factory"]
    print(
        f"patched {args.cloudinit}: dev_mode=true, bootstrap_url={af['bootstrap_url']}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
