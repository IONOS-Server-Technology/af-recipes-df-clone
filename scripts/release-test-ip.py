#!/usr/bin/env python3
"""Release a previously reserved ephemeral IONOS IP block.

Counterpart to reserve-test-ip.py. Must run with `if: always()` in the
workflow so the block is freed even if /compose, the ImageTester run, or
any step in between fails.
"""
import argparse
import sys

from ImageBuilder.Util.EphemeralIpBlock import EphemeralIpBlock


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uuid", required=True, help="UUID of the IP block to release")
    parser.add_argument("--name", default="", help="Name of the IP block (for logging only)")
    args = parser.parse_args()

    block = EphemeralIpBlock(args.name)
    block.uuid = args.uuid
    block.release_block()
    return 0


if __name__ == "__main__":
    sys.exit(main())
