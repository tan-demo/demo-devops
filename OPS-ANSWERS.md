# Part 7 — Ops Answers

## 1. EKS 1.33 → 1.35 upgrade, zero downtime

You cannot skip minors, so this is **1.33 → 1.34 → 1.35**, and for each minor the order is fixed by
the version-skew rules (nodes may trail the control plane, never lead it):

1. **Pre-flight (once):** scan for removed/deprecated APIs (`pluto`/`kubent`) and fix manifests;
   confirm every workload has ≥2 replicas, a PDB, and real readiness probes; review EKS *upgrade insights*.
2. **Control plane** to the next minor (EKS-managed, in place).
3. **Add-ons** to versions matching the new control plane — `kube-proxy`, `coredns`, `vpc-cni`, then
   EBS/EFS CSI. These must track the control-plane minor to avoid skew.
4. **Worker nodes** last — rolling replacement (managed node groups or Karpenter drift) that drains
   respecting PDBs and surges new nodes before removing old ones.

**Top 3 risks:** (1) **removed APIs** silently breaking workloads after the bump — mitigate with a
pre-flight `pluto` scan and manifest fixes; (2) **add-on/control-plane skew** (especially `vpc-cni` and
`kube-proxy`) causing pod-networking or DNS outages — upgrade add-ons in lockstep, one minor at a time;
(3) **node-rotation disruption** taking a service below capacity — enforce PDBs, ≥2 replicas, and surge.

## 2. Spot-reclaim alert storms (`KubeNodeUnreachable` at 3 AM)

A spot reclaim is an **expected, graceful** event (rebalance recommendation + ~2-min notice). The fix is
to make alerting distinguish *expected node loss* from *real failure*:

- Run AWS Node Termination Handler / Karpenter so a reclaimed node is **cordoned and drained** in an
  orderly way, and carries an interruption taint.
- **Inhibit** `KubeNodeUnreachable` for nodes that are tainted-for-interruption or under a known drain
  (Alertmanager inhibition rule), and add a `for:` window so the brief NotReady during normal replacement
  never pages.
- **Alert on impact, not on the node.** Page on what actually hurts users: pending pods above a threshold
  for N minutes, capacity shortfall, or SLO/error-budget burn — Karpenter replaces the node automatically,
  so a node leaving is not itself an incident.
- **Don't lose real failures:** keep a high-severity alert for nodes that go NotReady **without** an
  interruption taint and stay down past `for:`, plus the cluster-level capacity/SLO alerts above.

## 3. Cloudflare HTML not caching → mobile LCP 5s

Diagnose from the edge inward:

1. **Headers:** `curl -sI https://site/` and read **`cf-cache-status`**. `DYNAMIC` means Cloudflare isn't
   caching HTML (its default) — that points straight at missing cache rules.
2. **Origin `Cache-Control`:** if the origin returns `no-cache`/`private`/`max-age=0`, or a **`Set-Cookie`**
   on the HTML, Cloudflare won't cache it.
3. **Cache rules:** confirm a rule marks the HTML paths cache-**eligible** with an edge TTL (and a
   `Cache-Control` override if the origin is uncooperative). Without it, HTML is bypassed.
4. **Cookies:** a session cookie on every HTML response forces BYPASS — scope/strip cookies or use a rule
   that ignores them for anonymous pages.
5. **Origin:** measure origin TTFB directly (test record, grey-cloud); high origin render time inflates LCP
   even when caching is fixed.
6. **Re-verify:** the second request should show `cf-cache-status: HIT`; re-measure mobile LCP. HTML caching
   is necessary but not always sufficient — if LCP is still high it's usually the hero image (serve AVIF/WebP).

## 4. Application secrets on EKS

**External Secrets Operator (ESO) + AWS Secrets Manager** vs **Sealed Secrets (Bitnami)**:

| | ESO + Secrets Manager | Sealed Secrets |
|---|---|---|
| Source of truth | Central (Secrets Manager) | Ciphertext in Git, per cluster |
| Auth | IRSA / Pod Identity (no static creds) | Cluster sealing key |
| Rotation | Central, auto-reflected to clusters | Re-encrypt + re-commit per change |
| Multi-cluster | One store, N clusters sync | N clusters = N keys to manage |
| GitOps | Commit `ExternalSecret` (names only) | Commit encrypted values |

**Choice for a startup with multiple prod EKS clusters: ESO + AWS Secrets Manager.** A single central
store scales cleanly across clusters, IRSA gives least-privilege access with no long-lived credentials, and
rotation in Secrets Manager propagates everywhere automatically while Git stays free of secret values.
Sealed Secrets' per-cluster keys and manual re-encryption don't scale past a couple of clusters. The
trade-off accepted is a hard AWS dependency and Secrets Manager API cost — worth it for the operational
simplicity at multi-cluster scale.
