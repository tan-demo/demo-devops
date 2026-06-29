# Part 6 — Load Test, Scaling Proof & Observability

Run with: `docker compose exec toolbox /workspace/scripts/60-loadtest.sh` — it installs
kube-prometheus-stack (Prometheus + Grafana), applies the app's `ServiceMonitor` + `PrometheusRule`,
imports the Grafana dashboard, runs k6 **through the Ingress**, and prints HPA before/after + placement.

## Setup

- Load is driven by **k6 against the Ingress** (`http://…/api/quote`), not the pod directly.
- Ramp: 0→10 (30s) → 30 VUs (held ~2m) → 0 (30s), ≈3m. Each VU = 1 request + 0.5s sleep.
- App: HPA `minReplicas: 3`, each pod `requests.cpu=100m / limits.cpu=500m`; `/api/quote` burns
  **~100ms of real CPU** per request (busy-loop, not sleep), so load actually drives the CPU-based HPA.

## Measured results (this run — Apple Silicon, 4-node k3d)

| Metric | Value |
|--------|-------|
| Requests | **5588, 0 failed (100% `200`)** |
| Throughput | **31 req/s** |
| Latency | avg 142ms · med 130ms · **p95 220ms** · max 342ms |
| HPA | scaled **3 → 6** (CPU 4% → peak **354%** of the 60% target) |
| Placement after scale-out | **3 spot + 3 on-demand** — replicas stay balanced |

## Thresholds (justified from the baseline, not generic)

- `http_req_failed: rate<0.01` — measured **0%** failures; <1% flags a real regression while tolerating
  a stray timeout.
- `http_req_duration: p(95)<400ms` — the endpoint does ~100ms CPU **by design**; measured p95 under load
  is **220ms**, so 400ms is ~1.8× headroom over the loaded baseline before we call it degraded.

## HPA scale-out proof

`scripts/60-loadtest.sh` runs `kubectl get hpa -w` and `kubectl get events --watch-only` in the
background during the k6 run. Fresh logs land in:

- `loadtest/evidence/hpa-scale-out.log`
- `loadtest/evidence/pod-events.log`

A representative capture from a prior run is committed as
`loadtest/evidence/hpa-scale-out.sample.txt` (3 → 6 replicas under load).

Timeline from that run:
17:29  cpu: 3%/60%    replicas 3   (baseline)
17:30  cpu: 88%/60%   replicas 3→5 (load in)
17:30  cpu: 228%/60%  replicas 6
17:31  cpu: 354%/60%  replicas 6   (saturated)
17:32  cpu: 130%/60%  replicas 6   (load out)

At 6 replicas, `kubectl get pods -o wide` showed **3 spot + 3 on-demand** — the Part 2 capacity spread
still holds after scale-out.

## Where the bottleneck is

**The app's CPU**, by design. `/api/quote` burns ~100ms CPU/request, so a 0.5-core pod sustains ~5 req/s;
6 pods → ~30 req/s — exactly where throughput plateaued (31 req/s, p95 climbing to 220ms, CPU pinned). It
is **not** the Ingress (0 failures, trivial network) nor scheduling (pods placed fine across spot/on-demand).

## What I'd scale first in production

1. **Replicas via the HPA** (already wired) — the service is stateless and horizontally scalable, so more
   pods add throughput linearly… until the nodepool fills.
2. **Nodes via Karpenter** (Part 5) — provision more capacity (spot-preferred) so the HPA isn't blocked on
   schedulable nodes at higher RPS.
3. Tune the per-pod CPU limit only if single-request **latency** is the SLO — here the 100ms is inherent
   work, so horizontal scale is the right lever, not bigger pods.

## Alert rule

`charts/quote-api/templates/prometheusrule.yaml` (gated by `monitoring.enabled`) fires when the p95 of
`quote_request_duration_seconds` stays above **0.25s for 2m**. Justification: measured p95 under sustained
load is **220ms**, so 250ms held for 2 minutes means the endpoint is consistently past its loaded baseline
(HPA exhausted or nodes constrained) — the actionable "degraded" signal. The 2m `for` filters the brief
latency spike during scale-up.

## Dashboard

`loadtest/dashboard.json` is imported into Grafana by `scripts/60` (request rate, p95 latency, replica
count, CPU). A screenshot taken during the load test is in `loadtest/screenshots/`.
