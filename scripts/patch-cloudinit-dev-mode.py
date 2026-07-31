#!/usr/bin/env python3
"""Patch the cloud-init returned by /compose for the recipe-test leg it will boot on.

The live recipe test runs one of three legs, and each needs the ``application_factory``
block adjusted differently. ``--leg`` selects which:

``--leg ephemeral`` — the dev-mode run. af-api is deployed behind a plain-HTTP NodePort
Service (no TLS), so the VM has to reach the bootstrap endpoint over ``http://``. The
``cc_application_factory`` module rejects an ``http://`` bootstrap_url with a
non-loopback host unless dev mode is active (see af-cloud-init's ``_validate_config``),
so this leg sets ``dev_mode: true``, writes the ``.dev-mode-enabled`` sentinel, and
downgrades ``bootstrap_url`` from ``https://`` to ``http://``.

``--leg dev`` — the dev-cluster leg of a prod-mode run. The cloud-init comes from the
**real** dev af-api over https behind mTLS, so ``bootstrap_url`` is left alone. Dev mode
is still switched on, because a genuine production image only trusts the baked
dev-cluster signing key when dev mode is active (the IF-1399 trust tightening).

``--leg prod`` — the prod-cluster leg of a prod-mode run. This leg must stay in
**normal** mode: the archive is signed by the prod cluster and verified against the
always-trusted baked prod key, which is the production path the leg exists to
validate. So no ``dev_mode``, no ``.dev-mode-enabled``, no ``bootstrap_url`` rewrite —
only the af-finalize break-glass sentinel below, if it was asked for.

Independently of the leg, the ``.finalize-disabled`` break-glass sentinel is written
unless ``--keep-finalize`` is passed — that flag lets a caller test with af-finalize
actually running (its cloud-init cache scrub included) instead of short-circuiting it.
It is unrelated to dev mode: af-finalize's ``_break_glass()`` checks only that sentinel
or the ``af_finalize=off`` kernel argument. ``--leg prod --keep-finalize`` therefore
asks for nothing at all and is a documented no-op.

It is a CI-only transform — production cloud-init must never carry ``dev_mode``.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

CLOUD_CONFIG_HEADER = "#cloud-config"
DEV_MODE_SENTINEL = "/etc/app-factory/.dev-mode-enabled"
FINALIZE_SENTINEL = "/etc/app-factory/.finalize-disabled"

# Legs that run against a real cluster over https behind mTLS, so the bootstrap_url
# must not be downgraded. Only the ephemeral leg talks to a plain-HTTP NodePort.
_KEEPS_HTTPS = frozenset({"dev", "prod"})
# Legs that need dev mode: the ephemeral leg for the http relaxation, the dev-cluster
# leg so the production image trusts the baked dev-cluster signing key. The prod
# cluster leg stays in normal mode on the production trust path.
_NEEDS_DEV_MODE = frozenset({"ephemeral", "dev"})

LEGS = ("ephemeral", "dev", "prod")


def patch_cloud_init(text: str, *, leg: str, keep_finalize: bool = False) -> str:
    """Return *text* with the application_factory block patched for *leg*.

    Raises ValueError if *leg* is unknown, or if the document has no
    ``application_factory`` block or no ``bootstrap_url`` inside it — that would mean
    /compose returned something we do not understand, and silently shipping it
    unpatched would mask the problem.
    """
    if leg not in LEGS:
        raise ValueError(f"unknown leg: {leg!r} (expected one of {', '.join(LEGS)})")

    doc = yaml.safe_load(text)
    if not isinstance(doc, dict):
        raise ValueError("cloud-init is not a YAML mapping")

    af_cfg = doc.get("application_factory")
    if not isinstance(af_cfg, dict):
        raise ValueError("cloud-init has no 'application_factory' mapping")

    if not af_cfg.get("bootstrap_url"):
        raise ValueError("application_factory block has no 'bootstrap_url'")

    sentinels: list[str] = []
    if leg in _NEEDS_DEV_MODE:
        af_cfg["dev_mode"] = True
        sentinels.append(DEV_MODE_SENTINEL)
        if leg not in _KEEPS_HTTPS and af_cfg["bootstrap_url"].startswith("https"):
            af_cfg["bootstrap_url"] = af_cfg["bootstrap_url"].replace("https", "http", 1)
    if not keep_finalize:
        sentinels.append(FINALIZE_SENTINEL)

    # Leave write_files absent rather than emitting an empty list when there is
    # nothing to write (--leg prod --keep-finalize).
    if sentinels:
        doc["write_files"] = [
            {"content": "", "path": path, "append": True} for path in sentinels
        ]

    # safe_dump drops the leading '#cloud-config' comment that cloud-init
    # requires, so re-prepend it. sort_keys=False keeps /compose's key order.
    body = yaml.safe_dump(doc, sort_keys=False, allow_unicode=True)
    return f"{CLOUD_CONFIG_HEADER}\n{body}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "cloudinit",
        help="Path to the cloud-init YAML from /compose; patched in place",
    )
    parser.add_argument(
        "--leg",
        required=True,
        choices=LEGS,
        help="Which recipe-test leg this cloud-init will boot on. 'ephemeral' = the "
        "dev-mode run against the plain-HTTP af-api NodePort; 'dev' = the dev-cluster "
        "leg of a prod-mode run (dev mode on, https kept); 'prod' = the prod-cluster "
        "leg of a prod-mode run (normal mode, production trust path). Required — "
        "defaulting it would silently patch a leg the wrong way.",
    )
    parser.add_argument(
        "--keep-finalize",
        action="store_true",
        help="Do not write the .finalize-disabled break-glass sentinel — "
        "let af-finalize run for real (scrub included) on this VM. Applies to every "
        "leg; with --leg prod it leaves the cloud-init effectively unchanged.",
    )
    args = parser.parse_args()

    text = Path(args.cloudinit).read_text()

    try:
        patched = patch_cloud_init(text, leg=args.leg, keep_finalize=args.keep_finalize)
    except (ValueError, yaml.YAMLError) as exc:
        print(f"failed to patch cloud-init: {exc}", file=sys.stderr)
        return 1

    Path(args.cloudinit).write_text(patched)
    doc = yaml.safe_load(patched)
    af = doc["application_factory"]
    written = ", ".join(entry["path"] for entry in doc.get("write_files", [])) or "<none>"
    print(
        f"patched {args.cloudinit}: leg={args.leg}, "
        f"dev_mode={af.get('dev_mode', False)}, "
        f"bootstrap_url={af['bootstrap_url']}, write_files=[{written}]",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
