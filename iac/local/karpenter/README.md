# Part 5a — Karpenter for GPU AI inference (validate-only)

Current stable API: `karpenter.sh/v1` (NodePool) and `karpenter.k8s.aws/v1` (EC2NodeClass).

| File | Purpose |
|------|---------|
| `ec2nodeclass.yaml` | Shared GPU node class (AMI, subnets, SGs, disk, role) |
| `nodepool-gpu-spot.yaml` | GPU NodePool, **spot**, `weight: 100` (preferred) |
| `nodepool-gpu-ondemand.yaml` | GPU NodePool, **on-demand**, `weight: 10` (fallback) |

## How the requirements map

- **Spot preferred, on-demand fallback (weights):** two NodePools share one node class.
  Karpenter picks the highest-weight NodePool that can provision; when spot capacity is
  unavailable it falls back to the on-demand pool.
- **Proper taint:** both pools taint `nvidia.com/gpu=true:NoSchedule`, so only pods that
  tolerate the GPU taint land on these expensive nodes.
- **Consolidation that won't kill inference mid-request:** `consolidationPolicy: WhenEmpty`
  only removes nodes with **no** workload pods — a node serving a request is never
  consolidated. `consolidateAfter: 5m` and a `10%` disruption budget further smooth churn.
  Inference pods should also carry `karpenter.sh/do-not-disrupt: "true"` to block voluntary
  disruption while a request is in flight.
- **Sensible limits:** GPU caps per pool (`nvidia.com/gpu`) bound spend; on-demand is capped
  lower since it is only a fallback.

## Spot vs on-demand for AI inference (trade-off)

Spot GPU instances are 60–70% cheaper, which matters because GPUs dominate inference cost —
but they can be reclaimed with ~2 minutes notice, and reclaims often hit many nodes at once
when capacity is tight. For inference that is **stateless and horizontally scalable**, spot is
the right default: a reclaimed replica is simply replaced and load shifts to the others, so the
cost win outweighs the occasional disruption. The on-demand pool exists as a guaranteed
fallback so the service never drops to zero capacity during a spot shortage. The balance we
strike: prefer spot by weight for cost, keep a smaller on-demand pool for availability, and use
`do-not-disrupt` + PodDisruptionBudgets so in-flight requests drain cleanly rather than being
killed mid-response.

## Note on the GPU AMI

`alias: al2023@latest` is shown for brevity. In production, pin the GPU-optimized AMI variant
(AL2023 NVIDIA or Bottlerocket NVIDIA) via `amiSelectorTerms` so the NVIDIA drivers are present.
