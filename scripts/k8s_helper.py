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

    p = sub.add_parser("deploy")
    p.add_argument("name")
    p.add_argument("image")

    p = sub.add_parser("rollout-status")
    p.add_argument("deployment")
    p.add_argument("--timeout", default="120s")

    p = sub.add_parser("get-url")
    p.add_argument("service")
    p.add_argument("port", type=int)

    p = sub.add_parser("delete")
    p.add_argument("resources", nargs="+")

    args = parser.parse_args()
    k8s = K8sHelper(kubeconfig())

    if args.cmd == "deploy":
        k8s.apply({
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {"name": args.name},
            "spec": {
                "replicas": 1,
                "selector": {"matchLabels": {"app": args.name}},
                "template": {
                    "metadata": {"labels": {"app": args.name}},
                    "spec": {
                        "containers": [{
                            "name": "af-api",
                            "image": args.image,
                            "ports": [{"containerPort": 8000}],
                            "env": [{"name": "DEV_MODE", "value": "true"}],
                        }]
                    }
                }
            }
        })
        k8s.apply({
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {"name": args.name},
            "spec": {
                "selector": {"app": args.name},
                "ports": [{"port": 8000, "targetPort": 8000}],
            }
        })
    elif args.cmd == "rollout-status":
        k8s.rollout_status(args.deployment, args.timeout)
    elif args.cmd == "get-url":
        result = k8s.failsafe_kubectl("get", "svc", args.service, "-o", "jsonpath={.spec.clusterIP}")
        print(f"http://{str(result).strip()}:{args.port}")
    elif args.cmd == "delete":
        k8s.delete(*args.resources)

    return 0


if __name__ == "__main__":
    sys.exit(main())
