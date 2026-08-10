#!/usr/bin/env python3
"""Reserve an ephemeral IONOS IP block for a test run.

Runs before /compose so the VM's public IP (and thus its base_domain) is
known before the VM exists. Prints ip/uuid/base_domain as GITHUB_OUTPUT
(or to stdout when run outside GitHub Actions).
"""
import argparse
import os
import sys

from ImageBuilder.Util.EphemeralIpBlock import EphemeralIpBlock


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="Name for the IONOS IP block")
    args = parser.parse_args()

    block = EphemeralIpBlock(args.name)
    block.reserve_block()

    ip = block.ips[0]
    base_domain = ip.replace(".", "-") + ".sslip.io"

    lines = [
        f"name={args.name}",
        f"ip={ip}",
        f"uuid={block.uuid}",
        f"base_domain={base_domain}",
    ]

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as f:
            f.write("\n".join(lines) + "\n")
    else:
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
