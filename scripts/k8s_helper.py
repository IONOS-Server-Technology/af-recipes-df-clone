#!/usr/bin/env python3
"""CLI wrapper around K8sHelper for af-api deployment management."""
import argparse
import base64
import datetime
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


def reap_stale_af_api(k8s: K8sHelper, keep_name: str, max_age_seconds: int = 23400) -> None:
    """Delete leftover ephemeral af-api Deployments/Services from earlier runs
    whose own cleanup-af-api never ran (force-cancelled run, runner crash, etc).
    Age gate is 6.5 h: the pipeline's max runtime is 6 h, so anything older is a
    failed/orphaned run by definition — a concurrent in-flight run can never be
    that old, and the current run's name is excluded explicitly. Cross-branch on
    purpose (age is the safety filter). Best-effort: never blocks deploy."""
    try:
        out = str(k8s.failsafe_kubectl(
            "get", "deploy,svc", "-l", "af-api-ephemeral=true", "-o", "json",
        ))
        items = json.loads(out).get("items", [])
    except Exception as exc:
        print(f"reap: skipped ({exc})", file=sys.stderr)
        return
    now = datetime.datetime.now(datetime.timezone.utc)
    stale = []
    for it in items:
        meta = it.get("metadata", {})
        name = meta.get("name", "")
        ts = meta.get("creationTimestamp")
        if not name or name == keep_name or not ts:
            continue
        created = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if (now - created).total_seconds() > max_age_seconds:
            stale.append(f"{it.get('kind', '').lower()}/{name}")
    if stale:
        print(f"reap: deleting {len(stale)} stale af-api resource(s): {', '.join(stale)}")
        k8s.delete(*stale)


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

    p = sub.add_parser("reap-af-api")
    p.add_argument("--max-age-hours", type=float, default=6.5)

    p = sub.add_parser("describe")
    p.add_argument("name")

    p = sub.add_parser("logs")
    p.add_argument("name")
    p.add_argument("--tail", default="1000")

    p = sub.add_parser("list-pull-secrets")

    p = sub.add_parser("ensure-pull-secret")
    p.add_argument("registry")

    args = parser.parse_args()
    k8s = K8sHelper(kubeconfig())

    if args.cmd == "deploy":
        # Reap leftovers from earlier runs whose own cleanup never ran before
        # allocating anything new — self-heals orphan accumulation / NodePort
        # exhaustion. Age-gated, so concurrent in-flight runs are safe.
        reap_stale_af_api(k8s, args.name)
        # Service first so the NodePort is allocated and we can derive the
        # externally-reachable URL that has to be baked into the af-api
        # container as AF_API_URL — the per-branch deploy must not phone
        # home to the production af-api host that the default points at.
        k8s.apply({
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {"name": args.name, "labels": {"af-api-ephemeral": "true"}},
            "spec": {
                "type": "NodePort",
                "selector": {"app": args.name},
                "ports": [{"port": 8000, "targetPort": 8000}],
            }
        })
        node_port = str(k8s.failsafe_kubectl(
            "get", "svc", args.name,
            "-o", "jsonpath={.spec.ports[?(@.port==8000)].nodePort}",
        )).strip()
        if not node_port:
            raise RuntimeError(f"service {args.name} has no nodePort for port 8000")
        node_ip = str(k8s.failsafe_kubectl(
            "get", "nodes",
            "-o", "jsonpath={.items[0].status.addresses[?(@.type=='InternalIP')].address}",
        )).strip().split()[0]
        af_api_url = f"http://{node_ip}:{node_port}/api/v1"
        # Match the production code path: load the JWE key from env instead
        # of the DEV_MODE auto-generate branch. Without a shared key, each
        # uvicorn worker (Dockerfile starts --workers 2) builds its own
        # ephemeral key on startup, and /compose vs. /bootstrap round-robined
        # to different workers fail decryption. The caller passes a freshly
        # generated key per deployment in AF_API_JWE_PRIVATE_KEY_PEM.
        jwe_pem = os.environ.get("AF_API_JWE_PRIVATE_KEY_PEM")
        if not jwe_pem:
            raise RuntimeError("AF_API_JWE_PRIVATE_KEY_PEM env var not set")
        signing_key_pem = os.environ.get("AF_API_BOOTSTRAP_SIGNING_KEY_PEM")
        if not signing_key_pem:
            raise RuntimeError("AF_API_BOOTSTRAP_SIGNING_KEY_PEM env var not set")
        container_env = [
            {"name": "AF_API_URL", "value": af_api_url},
            {"name": "JWE_PRIVATE_KEY_PEM", "value": jwe_pem},
            {"name": "BOOTSTRAP_SIGNING_KEY_PEM", "value": signing_key_pem},
            # IF-1385: this deployment only ever serves ephemeral test/CI VMs, so
            # the Traefik it renders onto them must never mint real LE certs.
            {"name": "LE_CASERVER", "value": "https://acme-staging-v02.api.letsencrypt.org/directory"},
            # PR recipe logos are synced to the appfactory-dev bucket only, so the
            # ephemeral test af-api must serve that bucket's base URL.
            {"name": "AF_LOGO_BASE_URL", "value": "https://appfactory-dev.s3.eu-central-3.ionoscloud.com"},
        ]
        k8s.apply({
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {"name": args.name, "labels": {"af-api-ephemeral": "true"}},
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
                            # Image tag is branch-derived (mutable, reused across every run
                            # on that branch) — without this, a node with a cached image
                            # under the same tag can silently keep serving a stale build
                            # instead of the one just pushed by this run.
                            "imagePullPolicy": "Always",
                            "ports": [{"containerPort": 8000}],
                            "env": container_env,
                            "readinessProbe": {
                                "httpGet": {"path": "/api/v1/health", "port": 8000},
                                "periodSeconds": 2,
                                "failureThreshold": 30,
                            },
                        }]
                    }
                }
            }
        })
    elif args.cmd == "rollout-status":
        k8s.rollout_status(args.deployment, args.timeout)
    elif args.cmd == "get-url":
        node_port = str(k8s.failsafe_kubectl(
            "get", "svc", args.service,
            "-o", f"jsonpath={{.spec.ports[?(@.port=={args.port})].nodePort}}",
        )).strip()
        if not node_port:
            raise RuntimeError(f"service {args.service} has no nodePort for port {args.port}")
        node_ip = str(k8s.failsafe_kubectl(
            "get", "nodes",
            "-o", "jsonpath={.items[0].status.addresses[?(@.type=='InternalIP')].address}",
        )).strip().split()[0]
        print(f"http://{node_ip}:{node_port}")
    elif args.cmd == "delete":
        k8s.delete(*args.resources)
    elif args.cmd == "reap-af-api":
        reap_stale_af_api(k8s, "", int(args.max_age_hours * 3600))
    elif args.cmd == "describe":
        print("--- Deployment ---")
        print(str(k8s.failsafe_kubectl("describe", f"deployment/{args.name}")))
        print("--- Pods (selector app=" + args.name + ") ---")
        print(str(k8s.failsafe_kubectl("get", "pods", "-l", f"app={args.name}", "-o", "wide")))
        print("--- Pod events ---")
        print(str(k8s.failsafe_kubectl("describe", "pods", "-l", f"app={args.name}")))
    elif args.cmd == "logs":
        print("--- Pod logs (deployment=" + args.name + ", tail=" + args.tail + ") ---")
        print(str(k8s.failsafe_kubectl(
            "logs", f"deployment/{args.name}", f"--tail={args.tail}",
        )))
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
