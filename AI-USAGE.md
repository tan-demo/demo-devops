# AI Usage Disclosure

Heavy AI usage throughout — the brief expects it. What I optimized for is **verify, correct, and own**
the output: every deliverable was run locally (cluster up, `verify.sh`, reclaim drill, load test, CI gates)
before it stayed in the repo.

---

## Tools and where they were used

| Tool | Role | Parts |
|------|------|-------|
| **Claude Code (Opus 4.8)** | Primary author — scaffolding, code, manifests, docs | CORE 1–3, harness, Helm/ArgoCD, Parts 4–6 IaC/CI/load test, README |
| **Cursor** | Second-pass reviewer against the assignment brief | Golden Rule gaps, Part 6 evidence, doc polish → PR #16 |
| **OpenAI Codex** | Independent reviewer (same brief, different lens) | Portability (multi-arch toolbox), reclaim drill rigour, placement edge cases |

Version pins (kubectl/k3s 1.36, Helm 4, Karpenter `v1`, ArgoCD 3.4, etc.) were checked on official
release pages — not taken from model memory.

---

## Representative prompts that moved things forward

1. *"Self-contained `docker compose up`: toolbox with kubectl/helm/terraform/k6, k3d with 4 worker
   nodes, run `prepare.sh`, reach the API over a shared Docker network — reviewer runs nothing else."*
   → `toolbox/` + `k3dnet` + bind-mounted `scripts/` harness.

2. *"Part 2 placement: prefer spot, always ≥1 on-demand, spread across nodes but reschedule-safe when
   a spot node is drained — node affinity weights + topology spread, no hard-pin to on-demand."*
   → Helm chart placement policy; validated only after `scripts/25-reclaim-drill.sh` passed (see below).

3. *"Migrate the legacy GitLab pipeline by intent: hard-fail SAST, immutable git-SHA image tags, no AWS
   keys, no imperative kubectl deploy — GitOps owns rollout."*
   → Semgrep `--error`, Trivy HIGH/CRITICAL gate, cosign, GHCR push; deploy removed from CI.

---

## Where the AI was wrong or suboptimal — and how I caught it

### 1. Placement policy — wrong twice; caught by running the reclaim drill, not by reading YAML

**Symptom (iteration 1):** All 3 replicas on spot, 0 on on-demand — soft `topologySpreadConstraints`
(`ScheduleAnyway`) plus spot preference was outscored by the scheduler and ignored.

**Symptom (iteration 2):** Hard spread keyed on `kubernetes.io/hostname` gave a clean 2 spot + 1
on-demand — but draining a spot node left a replica **`Pending`** until uncordon. Root cause: a cordoned
node stays in its hostname domain at 0 pods, so the evicted pod violates `maxSkew: 1`.

**Fix:** Hard `DoNotSchedule` spread on **`acme.io/capacity`** (guarantees ≥1 on-demand and ≥1 spot;
reschedule-safe because the other spot node remains in the `spot` domain). Layer a **soft** hostname
spread on top for per-node distribution without re-introducing the drain wedge.

**Verify:** `scripts/25-reclaim-drill.sh` — curl loop ok/fail=0, no Pending pods, ≥1 on-demand retained.
This is exactly the trap the brief hints at ("think through what a hard constraint would do during the drill").

### 2. Stale dependencies — caught by Trivy, not by code review

The model pinned `fastapi==0.115.6` (training-era "latest"). **Trivy** flagged 3 **HIGH** CVEs in
transitive `starlette`. Bumped to current releases; pipeline green (Trivy 0 HIGH/CRITICAL, Semgrep clean).
Also replaced deprecated `@app.on_event("startup")` with FastAPI `lifespan` — another stale default.

### 3. Observability that looked done but wasn't — caught by opening Grafana under load

ServiceMonitor selected on `app.kubernetes.io/instance`, but Part 6 applied it with instance `qa` while
ArgoCD deploys `quote-api-dev` — Prometheus scraped nothing; two dashboard panels showed **No data**.
Fixed selector to stable `app.kubernetes.io/name` only; re-checked all four panels under k6 load.

### 4. Golden Rule bootstrap race — caught by reviewing against the brief literally (Cursor pass)

The brief says the reviewer runs `docker compose up -d` then immediately `./scripts/run-all.sh`. Our
entrypoint creates k3d in the background for several minutes; `run-all` could exec into the toolbox before
the cluster existed. **Fix (this PR):** `bootstrap.done` marker + compose healthcheck + host-side poll in
`run-all.sh` (up to 10 min). Verified: fresh clone → compose → run-all → `curl localhost:8080/api/quote`
without reading docs.

---

## Using AI to review my own work

After the first complete pass I ran **Codex** and **Cursor** against the checklist — deliberately
attacking, not authoring. I triaged every suggestion: apply if grounded in the brief, reject if
gold-plating.

**Applied from reviews:** multi-arch toolbox auto-detect, reclaim drill on a node that actually hosts
`quote-api`, broken→fix troubleshoot flow, k6 hard-fail on threshold breach, HPA `-w` capture in Part 6,
pytest in CI (replacing the legacy flaky npm gate in spirit), Mermaid diagram in README.

**Declined (with reasons):** OpenTelemetry tracing (bonus only); error-rate alert on a stateless quote
API that effectively never 5xxs; SHA tags everywhere locally (offline `dev` + `k3d import` is intentional);
speculative `/tmp` emptyDir when `readOnlyRootFilesystem` already works.

**Neither reviewer caught — I did:** the AWS production diagram drew **RDS** on a stateless in-memory app.
Removed it; a diagram is a claim — an inaccurate box is worse than a missing one.

---

## How I verify before keeping AI output

| Gate | What it catches |
|------|-----------------|
| `./scripts/run-all.sh` + host `curl` | Golden Rule end-to-end |
| `scripts/25-reclaim-drill.sh` | Placement reschedule under spot drain |
| `troubleshoot/verify.sh` | Part 3 fixes without cheating NetworkPolicy/nodes |
| `scripts/60-loadtest.sh` | k6 thresholds, HPA > 3, placement at scale |
| CI: Semgrep + pytest + Trivy + cosign | SAST, regressions, CVEs, signed image |
| `scripts/50-validate-tf.sh` | Karpenter dry-run + Cloudflare `terraform validate` |
| Grafana under load | Scrapes and dashboards actually work |

The pattern: **AI drafts fast; running the thing decides what stays.**
