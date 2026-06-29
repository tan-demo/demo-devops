# AI Usage Disclosure

## Tools

- **Claude Code (Claude Opus 4.8)** — used throughout: scaffolding the compose/k3d harness, writing
  the FastAPI service and Helm chart, the ArgoCD manifests, the Karpenter/Cloudflare IaC, the CI
  workflow, and the docs. Every artifact was run and verified locally before being kept (cluster up,
  `helm template`, `terraform validate`, `verify.sh`, **Semgrep** SAST + **Trivy** image CVE scan).
- Versions for all tooling were **verified against current docs** (Kubernetes/k3d/Helm/Terraform/k6/
  ArgoCD release pages) rather than taken from the model's memory.

## Representative prompts that moved things forward

1. *"Set up `docker compose up` so it self-bootstraps a k3d cluster with 4 workers + a toolbox
   container (kubectl/helm/terraform/k6), runs `prepare.sh`, and the toolbox reaches the API over a
   shared docker network."* → produced the `toolbox/` image + `entrypoint.sh` + `k3dnet` design.
2. *"Implement Part 2 placement: prefer spot, always ≥1 on-demand, spread across nodes but soft enough
   to survive a spot drain — with node affinity weights + topology spread."*
3. *"Migrate the legacy GitLab pipeline by intent: hard-fail Semgrep gate, git-SHA image tags, drop the
   hard-coded AWS keys and the manual kubectl deploy."*

## Where the AI was wrong / suboptimal, and how I caught it

**Placement: two wrong turns, both caught by running the actual reclaim drill — not by reading the
manifest.** Iteration 1 used a `topologySpreadConstraints` with `whenUnsatisfiable: ScheduleAnyway`
(soft) plus a strong spot affinity weight, assuming soft spread would naturally land one replica on the
on-demand node. Real placement showed **all 3 on spot, 0 on-demand** — the soft constraint was outscored
and ignored. Iteration 2 switched to a **hostname-keyed `DoNotSchedule` spread**, which *did* give a
clean 2 spot + 1 on-demand, and both the model and I assumed it was reschedule-safe. Running
`scripts/25-reclaim-drill.sh` proved that assumption **wrong**: draining a spot node left a replica
**`Pending`** and the rollout never returned to 3/3 until uncordon. Root cause: a cordoned node stays in
the hostname topology domain at 0 pods, so placing the evicted replica anywhere else pushes the skew to
2 (> maxSkew 1) and the hard constraint rejects it — exactly the trap the brief hints at ("think through
what a hard constraint would do during the drill"). Fix: key the **`DoNotSchedule` spread on
`acme.io/capacity` instead of hostname**. That still hard-guarantees ≥1 on-demand and ≥1 spot (skew can
never reach 3-0), but it *is* reschedule-safe — when one spot node is cordoned the `spot` capacity domain
still has its other node, so the evicted pod reschedules there. Re-ran the drill: **2 spot + 1 on-demand,
zero `Pending`, rollout back to 3/3, `curl` loop ok=40/fail=0, and the PDB correctly held ≥2 available
mid-drain.** (A strict 2:1 ratio is biased via a max-weight spot preference but is best-effort — the
scheduler's balanced-allocation scoring means it can't be hard-pinned without re-introducing the drain
trap; the hard guarantee we keep is "≥1 on-demand, always reschedulable".)

**Outdated dependency shipped HIGH CVEs (caught by the security gate, not by reading code).** The
model pinned `fastapi==0.115.6` — its training-era "latest". Running the image through **Trivy** (the
CI's HIGH/CRITICAL gate) flagged **3 HIGH CVEs** in the transitive `starlette 0.41.3` (DoS via Range
header merging; SSRF/NTLM credential theft via UNC paths) — which would have **failed the pipeline**. I
checked PyPI for current releases and bumped to `fastapi 0.138.1` (pulls patched `starlette 1.3.1`),
`uvicorn 0.49.0`, `prometheus-client 0.25.0`, then rebuilt and re-verified: Trivy **0 HIGH/CRITICAL**,
Semgrep **0 findings**, and a runtime smoke test (all four endpoints + the readiness flag) still green.
While there I also migrated the **deprecated** `@app.on_event("startup")` hook to FastAPI's current
`lifespan` handler — another stale-API default the model reached for from memory.

**Two smaller corrections:**
- The model first pinned tool versions from memory (kubectl 1.31, etc.). I checked the release pages and
  found the current stable set (kubectl/k3s 1.36, Helm 4, k6 v2); I also had to **override the k3d
  default k3s image** so the server version matched the client and avoided a version-skew warning.
- The ArgoCD install initially failed (`applicationsets` CRD annotation too large for client-side
  apply). The fix was `kubectl apply --server-side`.
