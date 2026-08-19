#!/usr/bin/env python3
"""Assert that N VMs' bootstrap logs arrived and stayed attributable (IF-1310).

Reads af-api's container log on stdin and derives everything from it. Nothing is
queried, because the endpoint holds no state -- the log IS the record:

    kubectl logs deployment/af-api-<branch> --tail=-1 | verify_bootstrap_log.py

``--tail=-1`` is load-bearing. k8s_helper.py defaults to 1000, and the install-log
lines are sent first, so a truncated read reports them as "never arrived" when they
did. An instrument that silently cuts its input gives a plausible wrong answer.

Criteria, always:

* at least one bootstrap appears -- if none did, either no VM sent or af-api logged
  nothing, and both are failures of the thing under test;
* every bootstrap that appears received BOTH log sources, the install log and the
  journal;
* no stream hit a per-stream cap, which would mean a silently incomplete log.

With ``--expect N``, additionally: exactly N distinct bootstraps. That is the
replica scenario, where N identical VMs are booted precisely to show they stay N
attributable groups. It is deliberately not the default: on an ordinary run a leg can
fail before its VM ever boots, and an exact count would then report a logging failure
for something that never reached the logging.

Grouping is by the ``correlation_id`` af-api derives from the bootstrap token, so
ten VMs logging an identical "system started" stay ten attributable groups. That is
the property the whole design rests on, and a client-supplied id could not prove it.

Reading the log rather than a counter also makes the worker count irrelevant: every
worker of a container writes to the same stdout.

Exits 1 when a criterion fails, 2 on a usage error.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict

#: What the forwarder tags its streams with: one per source, plus that source's
#: stderr, which carries the follower's own diagnostics rather than log content.
LOG_SOURCES = ("install", "journal")
DIAGNOSTIC_SOURCES = ("install-err", "journal-err")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--expect",
        type=int,
        default=None,
        metavar="N",
        help="Require exactly N distinct bootstraps. For the replica scenario; "
        "omitted, any number of bootstraps is accepted as long as there is one.",
    )
    args = parser.parse_args()
    expected = args.expect

    records: dict[str, int] = defaultdict(int)
    per_source: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    streams_opened: dict[str, int] = defaultdict(int)
    reported_totals: dict[str, int] = defaultdict(int)
    capped: dict[str, str] = {}
    denied = 0
    parsed = 0

    for raw in sys.stdin:
        raw = raw.strip()
        if not raw or '"event"' not in raw:
            continue
        try:
            entry = json.loads(raw)
        except ValueError:
            # af-api logs one JSON object per line; anything else is not ours.
            continue
        parsed += 1
        event = entry.get("event")

        if event == "bootstrap_log_denied":
            denied += 1
            continue

        cid = entry.get("correlation_id")
        if not cid:
            continue

        if event == "bootstrap_log_line":
            records[cid] += 1
            per_source[cid][entry.get("source", "?")] += 1
        elif event == "bootstrap_log_opened":
            streams_opened[cid] += 1
        elif event == "bootstrap_log_closed":
            reported_totals[cid] += int(entry.get("records") or 0)
        elif event == "bootstrap_log_capped":
            capped[cid] = str(entry.get("reason"))

    all_cids = sorted(set(records) | set(streams_opened))

    print("=== IF-1310: bootstrap log arrival ===")
    print(f"JSON log records read : {parsed}")
    wanted = f" (expected exactly {expected})" if expected is not None else " (expected at least 1)"
    print(f"distinct bootstraps   : {len(all_cids)}{wanted}")
    if denied:
        print(f"denied streams        : {denied}  <-- token rejected, check expiry/scrub")
    print()

    columns = ("correlation_id", "records", *LOG_SOURCES, *DIAGNOSTIC_SOURCES, "streams")
    header = f"{columns[0]:18s}" + "".join(f"{c:>13s}" for c in columns[1:])
    print(header)
    print("-" * len(header))

    failures: list[str] = []
    for cid in all_cids:
        sources = per_source[cid]
        row = f"{cid:18s}{records[cid]:>13d}"
        row += "".join(f"{sources.get(s, 0):>13d}" for s in (*LOG_SOURCES, *DIAGNOSTIC_SOURCES))
        row += f"{streams_opened[cid]:>13d}"
        print(row)

        for source in LOG_SOURCES:
            if not sources.get(source):
                failures.append(f"{cid}: no {source} lines")
        if cid in capped:
            failures.append(f"{cid}: stream hit a cap ({capped[cid]}) — log is incomplete")
        # More than one stream per bootstrap means the forwarder reconnected. Not a
        # failure: an Envoy idle cut is routine and reconnecting is the design. Worth
        # printing, because it is also the only place a reconnect becomes visible.
        if streams_opened[cid] > 1:
            print(f"  note: {cid} opened {streams_opened[cid]} streams (reconnects)")

    print()
    if not all_cids:
        failures.insert(
            0,
            "no bootstrap reached this endpoint at all -- either no VM sent, or "
            "BOOTSTRAP_LOG_EMIT was not 'content' so nothing was logged",
        )
    elif expected is not None and len(all_cids) != expected:
        detail = (
            " -- fewer means some VMs did not send"
            if len(all_cids) < expected
            else " -- more means something else streamed to this endpoint"
        )
        failures.insert(
            0, f"expected {expected} distinct bootstraps, log shows {len(all_cids)}{detail}"
        )

    if failures:
        print("FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print(
        f"OK: {len(all_cids)} VMs appear as {len(all_cids)} distinguishable bootstraps, "
        "each with install-log and journal lines."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
