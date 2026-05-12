#!/usr/bin/env python3
"""CLI wrapper around K8sHelper for af-api deployment management."""
import argparse
import base64
import json
import os
import sys

from ImageBuilder.Util.K8sHelper import K8sHelper

# Shared pull secret name used by every per-branch af-api deployment.
# The Harbor credentials behind it are identical across runs, so a single
# secret in the default namespace is created/updated idempotently before
# each deploy and referenced via imagePullSecrets.
PULL_SECRET_NAME = "harbor-imagefactory-pull"


def kubeconfig() -> str:
    kc = os.environ.get("KUBECONFIG_CONTENT")
    if not kc:
        raise RuntimeError("KUBECONFIG_CONTENT env var not set")
    return kc


def ensure_pull_secret(k8s: K8sHelper, registry: str) -> None:
    username = os.environ.get("HARBOR_USERNAME")
    password = os.environ.get("HARBOR_PASSWORD")
    if not username or not password:
        raise RuntimeError("HARBOR_USERNAME / HARBOR_PASSWORD env vars not set")
    auth = base64.b64encode(f"{username}:{password}".encode()).decode()
    dockerconfig = {"auths": {registry: {"username": username, "password": password, "auth": auth}}}
    dockerconfig_b64 = base64.b64encode(json.dumps(dockerconfig).encode()).decode()
    k8s.apply({
        "apiVersion": "v1",
        "kind": "Secret",
        "type": "kubernetes.io/dockerconfigjson",
        "metadata": {"name": PULL_SECRET_NAME},
        "data": {".dockerconfigjson": dockerconfig_b64},
    })


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

    p = sub.add_parser("describe")
    p.add_argument("name")

    p = sub.add_parser("list-pull-secrets")

    p = sub.add_parser("ensure-pull-secret")
    p.add_argument("registry")

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
                        "imagePullSecrets": [{"name": PULL_SECRET_NAME}],
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
    elif args.cmd == "describe":
        print("--- Deployment ---")
        print(str(k8s.failsafe_kubectl("describe", f"deployment/{args.name}")))
        print("--- Pods (selector app=" + args.name + ") ---")
        print(str(k8s.failsafe_kubectl("get", "pods", "-l", f"app={args.name}", "-o", "wide")))
        print("--- Pod events ---")
        print(str(k8s.failsafe_kubectl("describe", "pods", "-l", f"app={args.name}")))
    elif args.cmd == "list-pull-secrets":
        print(str(k8s.failsafe_kubectl(
            "get", "secrets",
            "--field-selector=type=kubernetes.io/dockerconfigjson",
            "-o", "custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp",
        )))
    elif args.cmd == "ensure-pull-secret":
        ensure_pull_secret(k8s, args.registry)

    return 0


if __name__ == "__main__":
    sys.exit(main())
