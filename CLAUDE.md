# Claude working notes for af-recipes

## DO NOT propose `kubectl port-forward` for af-api connectivity

For Runner→af-api `/compose` and VM→af-api `/bootstrap`, `kubectl port-forward` is **not a valid solution** and must not be suggested.

**Why:**
- The IF runner is private and behind NAT. `kubectl port-forward` on the runner listens on its localhost. The public IONOS test VM cannot reach a private runner's localhost — there is no IP-level path.
- Even for the runner-only direction port-forward only adds an extra hop through the k8s API server. The architectural fix is making the Service directly routable, not tunnelling.
- The runner cluster is intentionally fully NATted; port-forwarding rules will not be added on the runner side.

**Use instead:**
- `Service: NodePort` (if test-cluster nodes are routable from runner and VM)
- `Service: LoadBalancer`
- `Ingress` with DNS

If reachability is unclear, ask which exposure mechanism fits the infra — do not paper over with a tunnel.
