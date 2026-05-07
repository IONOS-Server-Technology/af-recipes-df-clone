#!/usr/bin/env python3
"""CLI wrapper around K8sHelper for af-api deployment management."""
import argparse
import os
import sys

from ImageBuilder.Util.K8sHelper import K8sHelper


def kubeconfig() -> str:
    kc = os.environ.get("KUBECONFIG_CONTENT")
    if not kc:
        raise RuntimeError("KUBECONFIG_CONTENT env var not set")
    return kc


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("set-image")
    p.add_argument("deployment")
    p.add_argument("container")
    p.add_argument("image")

    p = sub.add_parser("rollout-status")
    p.add_argument("deployment")
    p.add_argument("--timeout", default="120s")

    p = sub.add_parser("port-forward")
    p.add_argument("resource")
    p.add_argument("ports")
    p.add_argument("--pid-file", required=True)

    p = sub.add_parser("delete")
    p.add_argument("resources", nargs="+")

    args = parser.parse_args()
    k8s = K8sHelper(kubeconfig())

    if args.cmd == "set-image":
        k8s.set_image(args.deployment, args.container, args.image)
    elif args.cmd == "rollout-status":
        k8s.rollout_status(args.deployment, args.timeout)
    elif args.cmd == "port-forward":
        proc = k8s.port_forward(args.resource, args.ports)
        with open(args.pid_file, "w") as f:
            f.write(str(proc.pid))
    elif args.cmd == "delete":
        k8s.delete(*args.resources)

    return 0


if __name__ == "__main__":
    sys.exit(main())
