# AI Usage Disclosure

## Tools

- **Claude Code (Claude Opus 4.8)** — used throughout: scaffolding the compose/k3d harness, writing
  the FastAPI service and Helm chart, the ArgoCD manifests, the Karpenter/Cloudflare IaC, the CI
  workflow, and the docs. Every artifact was run and verified locally before being kept (cluster up,
  `helm template`, `terraform validate`, `verify.sh`, **Semgrep** SAST + **Trivy** image CVE scan).
- Versions for all tooling were **verified against current docs** (Kubernetes/k3d/Helm/Terraform/k6/
  ArgoCD release pages) rather than taken from the model's memory.
- **OpenAI Codex** and **Cursor** — used as *independent reviewers* of the finished submission (a
  second and third pair of eyes), not as authors. Codex scored it 88/100, Cursor 92/100; both
  returned concrete, actionable critiques. I treated their output the same way I treat any AI output:
  triage it against the brief, accept what's grounded, reject what's gold-plating. See the review
  loop below.

## Using AI to *review* my own work — and triaging the reviewers

Once the submission was "done", I ran it past two other models specifically to attack it. This was
deliberately a different mode from authoring: the value of a reviewer is in what it catches, and the
value of *me* is in deciding which catches are real.

**Codex (88/100) surfaced four real defects on the strict Golden Rule path — all fixed:**
- `toolbox/Dockerfile` hard-defaulted `TARGETARCH=arm64`, so an Intel reviewer running the Golden
  Rule could pull arm64 binaries and fail. Fixed by **auto-detecting the arch** (`uname -m`) at build
  time and dropping the build arg entirely — verified by building + running the image (every tool
  reports the host arch).
- `run-all.sh` skipped the Part 2 **reclaim drill** by default, so the headline resilience proof
  didn't run on a plain `run-all`. Now the drill runs by default; only the heavy Part 6 load test
  (full kube-prometheus-stack) stays opt-in.
- Placement only hard-spread by capacity, not "across nodes". Added a **soft `hostname` spread**
  (`ScheduleAnyway`) layered on top — node distribution without re-introducing the drain wedge.
- `scripts/60` swallowed k6's exit code (`|| true`), making the SLO thresholds decorative. It now
  captures the code, prints the HPA/placement evidence, then **exits non-zero** on a breach.

**Cursor (92/100) gave ten suggestions — I implemented four and deliberately declined five.** The
declines matter as much as the accepts, because "knowing what to skip" is the skill the brief calls
out:
- *Implemented:* the **broken→fix** troubleshooting flow (apply the broken manifest, show the failure,
  then fix — matching the brief's "incident handoff" framing; the broken file existed but was unused);
  an explicit **Part 6 pointer + teardown** under the Golden Rule; a **CI status badge**; and a
  **GitOps note** that ArgoCD syncs published `main`, not the local working copy.
- *Declined, with reasons:* OpenTelemetry tracing (the review itself labelled it a "bonus" — pure
  gold-plating); a second Mermaid diagram (the draw.io SVG supersedes it — redundant clutter); an
  error-rate alert (a stateless quote API effectively never 5xxs, so the rule would never fire —
  decorative); SHA-everywhere image tags (the offline `dev` tag + `k3d image import` is an
  intentional choice for the no-registry demo path); and a `/tmp` tmpfs (the app is verified running
  with `readOnlyRootFilesystem` — adding it "just in case" is speculative).

**The catch neither reviewer made — a stale question did.** A simple "*why does the AWS diagram have
RDS?*" exposed that the production diagram drew a database onto a **stateless** app (it returns a
random in-memory quote — no persistence). I removed RDS and its data edge. The lesson reinforced: a
diagram is a claim about the system, and an inaccurate claim is worse than a missing one — so the
diagram should show only what the workload actually uses (kept GPU pods and ESO, which the brief
grounds; dropped the DB, which nothing did).

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
trap; the hard guarantee we keep is "≥1 on-demand, always reschedulable".) On top of the hard *capacity*
spread the final chart **also layers a *soft* `kubernetes.io/hostname` spread (`ScheduleAnyway`)**: the
thing iteration 1 got wrong was using a soft spread *as the only control* (it was outscored → all on spot);
used *additively* under the hard capacity guarantee it is safe and gives the per-node distribution the brief
asks for ("replicas spread across nodes") without re-introducing the drain wedge.

**Outdated dependency shipped HIGH CVEs (caught by the security gate, not by reading code).** The
model pinned `fastapi==0.115.6` — its training-era "latest". Running the image through **Trivy** (the
CI's HIGH/CRITICAL gate) flagged **3 HIGH CVEs** in the transitive `starlette 0.41.3` (DoS via Range
header merging; SSRF/NTLM credential theft via UNC paths) — which would have **failed the pipeline**. I
checked PyPI for current releases and bumped to `fastapi 0.138.1` (pulls patched `starlette 1.3.1`),
`uvicorn 0.49.0`, `prometheus-client 0.25.0`, then rebuilt and re-verified: Trivy **0 HIGH/CRITICAL**,
Semgrep **0 findings**, and a runtime smoke test (all four endpoints + the readiness flag) still green.
While there I also migrated the **deprecated** `@app.on_event("startup")` hook to FastAPI's current
`lifespan` handler — another stale-API default the model reached for from memory.

**Observability *looked* done but wasn't — the dashboard had "No data" panels.** The chart shipped a
ServiceMonitor + a Grafana dashboard and `scripts/60` installed kube-prometheus-stack, so on paper Part 6
was complete. Only when I actually opened Grafana under load did two of the four panels (request rate, p95
latency) show **No data**. `kubectl` traced it: the ServiceMonitor selected on `app.kubernetes.io/instance`
too, but `scripts/60` rendered it with `helm template qa …` (instance `qa`) while the app is deployed by
ArgoCD with instance `quote-api-dev` — so the selector matched **no** Service and Prometheus scraped
nothing (`quote_requests_total` was empty). Fixed by selecting on the **stable** `app.kubernetes.io/name`
only; re-verified that the counter + latency histogram now appear in Prometheus and all four panels
populate. The lesson the brief is testing: *"the manifests exist and `helm lint`s"* is not *"it works"* —
the dashboard had to be looked at.

**Two smaller corrections:**
- The model first pinned tool versions from memory (kubectl 1.31, etc.). I checked the release pages and
  found the current stable set (kubectl/k3s 1.36, Helm 4, k6 v2); I also had to **override the k3d
  default k3s image** so the server version matched the client and avoided a version-skew warning.
- The ArgoCD install initially failed (`applicationsets` CRD annotation too large for client-side
  apply). The fix was `kubectl apply --server-side`.
