#!/usr/bin/env python3
"""Resolve the pipeline's test_against input into concrete target facts.

The test_against input controls which cluster(s) to test against and whether to
build the ephemeral image. This script validates and normalizes that input,
emitting GitHub Actions-compatible output suitable for appending to $GITHUB_OUTPUT.

Valid values: ephemeral, dev, prod, dev+prod (or empty/None for the default).

Examples:
    TEST_AGAINST_RAW=ephemeral python3 scripts/resolve-test-target.py
    TEST_AGAINST_RAW=dev+prod python3 scripts/resolve-test-target.py
    TEST_AGAINST_RAW= python3 scripts/resolve-test-target.py  # defaults to ephemeral
"""

import os
import sys
from typing import NamedTuple


class Target(NamedTuple):
    """Resolved test target configuration.

    Attributes:
        test_against: The normalized input value (one of the valid set).
        clusters: Space-separated cluster names to test against.
        build_ephemeral: Whether the ephemeral image must be built.
    """

    test_against: str
    clusters: str
    build_ephemeral: bool


# The valid test_against values, each mapped to (clusters, build_ephemeral).
# This is the single source of truth: validation below checks membership here, so
# there is no second list of names to keep in step.
TARGET_CONFIG = {
    "ephemeral": ("ephemeral", True),
    "dev": ("dev", False),
    "prod": ("prod", False),
    "dev+prod": ("dev prod", False),
}


def resolve(raw: str) -> Target:
    """Resolve the raw test_against input to a Target.

    Args:
        raw: The raw input string (may be empty, None-like, or a valid value).

    Returns:
        A Target with the resolved configuration.

    Raises:
        ValueError: If raw is not empty and not in the valid set.
    """
    # Empty or whitespace-only input defaults to ephemeral.
    if not raw or not raw.strip():
        raw = "ephemeral"
    else:
        raw = raw.strip()

    if raw not in TARGET_CONFIG:
        raise ValueError(
            f"invalid test_against value: {raw!r}. "
            f"Allowed values: {', '.join(sorted(TARGET_CONFIG))}"
        )

    clusters, build_ephemeral = TARGET_CONFIG[raw]
    return Target(test_against=raw, clusters=clusters, build_ephemeral=build_ephemeral)


def main() -> int:
    """Read test_against from environment, resolve it, and emit GitHub Actions output.

    Reads:
        TEST_AGAINST_RAW: The raw input value (or empty for default).

    Outputs:
        On success, prints three lines to stdout (for $GITHUB_OUTPUT):
            test_against=<value>
            clusters=<space-separated clusters>
            build_ephemeral=<true|false>

        On error, prints a GitHub Actions error annotation to stderr and exits 1:
            ::error::<message>

    Returns:
        0 on success, 1 on error.
    """
    raw = os.environ.get("TEST_AGAINST_RAW", "")

    try:
        target = resolve(raw)
    except ValueError as exc:
        print(f"::error::{exc}", file=sys.stderr)
        return 1

    # Emit output in lowercase boolean format.
    build_ephemeral_str = "true" if target.build_ephemeral else "false"
    print(f"test_against={target.test_against}")
    print(f"clusters={target.clusters}")
    print(f"build_ephemeral={build_ephemeral_str}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
