# quote-api — DevOps Take-Home

[![ci](https://github.com/tan-demo/demo-devops/actions/workflows/ci.yml/badge.svg)](https://github.com/tan-demo/demo-devops/actions/workflows/ci.yml)

A small HTTP quote API, shipped GitOps-style (ArgoCD) onto a local multi-node k3d cluster that
simulates a mixed **spot / on-demand / GPU** nodepool environment.

- **Public image:** `ghcr.io/tan-demo/quote-api` (tagged by git SHA)
- Everything runs locally in Docker — no cloud account needed.

---

## Quick start (the Golden Rule)

```bash
git clone https://github.com/tan-demo/demo-devops && cd demo-devops
docker compose up -d          # k3d cluster (4 workers) + toolbox + node labels/taints
./scripts/run-all.sh          # or run scripts/NN-*.sh one by one
curl http://localhost:8080/api/quote
```

`docker compose up -d` is self-contained: it builds a toolbox image (kubectl/helm/terraform/k6),
creates a k3d cluster with **4 worker nodes**, and runs `troubleshoot/prepare.sh` to label/taint
them. `run-all.sh` then installs ArgoCD, deploys the app via an ArgoCD Application, and runs the
remaining steps (including the Part 2 reclaim drill). Scripts are idempotent and bind-mounted into
the toolbox. The toolbox image **auto-detects** its arch, so this works on Intel and Apple Silicon
with no env var.

```bash
# Part 6 (load test + Prometheus/Grafana) is opt-in — it installs the full kube-prometheus-stack:
docker compose exec toolbox /workspace/scripts/60-loadtest.sh

# Tear everything down (deletes the k3d cluster, then the toolbox + network):
./scripts/destroy.sh
```

> **GitOps note:** ArgoCD syncs the **published `main`** of this repo, not your local working copy.
> Local chart edits only reach the cluster after a push — or apply them directly for a quick test
> with `helm template charts/quote-api | kubectl apply -f -`.

---

## Architecture

![local architecture](docs/local-architecture.svg)

> Editable source: [`docs/local-architecture.drawio`](docs/local-architecture.drawio) (open in [draw.io](https://app.diagrams.net/)).

### Placement policy (Part 2)

With 3 replicas: **≥1 on-demand guaranteed, the rest biased to spot**, never control-plane or GPU.

- **Required** node affinity restricts pods to the `acme.io/capacity ∈ {spot, on-demand}` pool —
  excludes the (untainted) control-plane node and the GPU node.
- **`topologySpreadConstraints` keyed on `acme.io/capacity`, `DoNotSchedule`, maxSkew 1.** This
  guarantees the spot/on-demand split can never reach 3-0 or 0-3 — so **≥1 replica is always on
  on-demand**. Crucially it is keyed on *capacity, not hostname*: when a spot node is cordoned during
  the reclaim drill, the `spot` domain still has its other node, so the evicted pod reschedules with **no
  `Pending`** (a hostname-keyed hard spread does *not* survive this — the cordoned node stays in its own
  domain and wedges the pod; see `AI-USAGE.md` for how the drill caught that).
- **A second, *soft* spread keyed on `kubernetes.io/hostname` (`ScheduleAnyway`, maxSkew 1)** gives the
  scheduler a best-effort signal to put replicas on *different nodes* (what the brief means by "spread
  across nodes"). Being soft, it never wedges a reschedule the way a hard hostname spread does — it just
  loses to the hard capacity guarantee when the two disagree.
- **Preferred** affinity (max weight) for spot gives the cost bias. A strict 2:1 ratio is best-effort —
  the scheduler's scoring means the spot majority isn't hard-guaranteed; the *guarantee* we keep is
  "≥1 on-demand, always reschedulable", which is what the brief asks for.
- We deliberately do **not** *hard*-pin by hostname or by capacity-to-on-demand — both defeat
  rescheduling during a reclaim (hence hostname spread is soft, capacity spread is hard). `scripts/25`
  now selects a **spot node that is actually hosting a `quote-api` pod**, drains it, keeps a curl loop
  running, and fails if there are request failures, Pending pods, loss of on-demand placement, or any pod
  lands outside the spot/on-demand pool.

### Bonus — how this runs in production on AWS

![quote-api in production on AWS](docs/aws-architecture.svg)

> Editable source: [`docs/aws-architecture.drawio`](docs/aws-architecture.drawio) (open in [draw.io](https://app.diagrams.net/)).
> The service is stateless today, so the diagram does not invent a database dependency; RDS would be added
> only if quotes/admin metadata become durable application data.

---

## Script reference

| Script | Does | When |
|--------|------|------|
| `scripts/run-all.sh` | runs the core steps + the 25 reclaim drill in the toolbox (60 load test opt-in), then sets up local access (kubeconfig + ArgoCD) | after `docker compose up -d` |
| `scripts/10-install-argocd.sh` | installs the ArgoCD controller (server-side apply) | bootstrap |
| `scripts/15-build-image.sh` | builds the app image and `k3d image import`s it for offline runs | before deploy |
| `scripts/20-deploy.sh` | applies the AppProject + `applications-dev` app-of-apps → ArgoCD deploys quote-api | deploy |
| `scripts/25-reclaim-drill.sh` | drains a spot node that hosts `quote-api`, asserts the service stays up and placement survives, then uncordons | resilience demo |
| `scripts/40-troubleshoot.sh` | applies `troubleshoot/fixed-app.yaml` and runs `verify.sh` | Part 3 |
| `scripts/50-validate-tf.sh` | `terraform fmt -check` / `init -backend=false` / `validate` (Cloudflare) | Part 5 |
| `scripts/60-loadtest.sh` | installs kube-prometheus-stack, runs k6 through the Ingress, captures HPA scale-out | Part 6 |
| `scripts/access.sh` | writes a host-usable kubeconfig + prints the ArgoCD login/URLs (run on the host) | to use kubectl / ArgoCD UI |
| `scripts/destroy.sh` | deletes the k3d cluster, then `docker compose down` + removes the host kubeconfig (run on the host) | full teardown |

---

## Accessing the cluster & ArgoCD

`run-all.sh` prints this at the end; you can also run it any time with **`./scripts/access.sh`**.
The cluster and toolbox run inside Docker, so the in-cluster kubeconfig points at
`host.docker.internal` (not resolvable from the host) — `access.sh` writes a host-usable copy.

- **App** (already exposed): `curl http://localhost:8080/api/quote`
- **kubectl from the host:**
  ```bash
  ./scripts/access.sh                       # writes ~/.kube/k3d-devops.yaml
  export KUBECONFIG=~/.kube/k3d-devops.yaml
  kubectl get nodes
  ```
  (Or skip the host setup entirely: `docker compose exec toolbox kubectl get pods -A`.)
- **ArgoCD UI:**
  ```bash
  export KUBECONFIG=~/.kube/k3d-devops.yaml
  kubectl port-forward -n argocd svc/argocd-server 8081:443
  # browse https://localhost:8081 (accept the self-signed cert), login: admin / <printed password>
  ```

---

## Design decisions & trade-offs

- **`/api/quote` burns real CPU (~100ms), not `sleep`.** The endpoint runs a busy-loop
  (`time.perf_counter`) so each request actually consumes CPU — that is what makes the Part 2
  CPU-based HPA scale out and the Part 6 load test meaningful (a `sleep` would idle without driving
  the autoscaler). Readiness uses FastAPI's `lifespan` handler, not the deprecated `on_event`.
- **App lives at `app/quote-api/`.** A service-named folder (not a flat `app/`) keeps the build context
  per-service, so adding a second service or wiring its own CI job is just another folder.
- **Single repo (monorepo).** A production setup would split app / infra / gitops-config repos for
  ownership boundaries and to avoid CI-commit loops; here a monorepo keeps the Golden Rule at one clone.
- **k3d inside compose via the toolbox.** The toolbox mounts the Docker socket and creates k3d node
  containers on a shared `k3dnet` network, so it reaches the API at `k3d-devops-serverlb:6443` without
  host-networking quirks.
- **Image built + imported locally.** Pods use `imagePullPolicy: IfNotPresent` against the
  k3d-imported image, so the demo runs offline; the same image is published to GHCR by CI, tagged
  by git SHA. To pull from the registry instead, set `image.tag` to a published SHA and `pullPolicy: Always`.
- **Observability is GitOps-managed.** ServiceMonitor / PrometheusRule / dashboard live in the Helm
  chart (gated by `monitoring.enabled`); kube-prometheus-stack itself is installed by `scripts/60`.
- **Latest stable, verified.** kubectl 1.36 / k3s 1.36 / Helm 4 / Terraform 1.15 / k6 v2 / ArgoCD 3.4 —
  pinned and checked against current docs (not from memory).
- **What we cut:** multi-env (staging/prod) is structured (chart `values/`, ArgoCD app stubs) but only
  **dev** is wired locally; Part 5 is validate-only (no live cloud).

---

## Troubleshooting notes (reviewer machine)

- **Port 8080 in use.** The Ingress is published on host `8080`. Change the `ports` mapping in
  `toolbox/k3d-config.yaml` if it clashes, then `docker compose up -d` again.
- **Memory.** A 5-node k3d cluster + ArgoCD + kube-prometheus-stack wants ~6–8 GB given to Docker.
  If pods stay `Pending`, raise Docker Desktop's memory, or skip `scripts/60` (the heavy step).
- **Architecture.** The toolbox image **auto-detects** the build arch (`uname -m` → `amd64`/`arm64`),
  so `docker compose up -d` just works on both Apple Silicon and Intel/CI — no env var to set.
- **Part 6 is opt-in.** `run-all.sh` runs the core steps **plus the 25 reclaim drill** by default, but
  skips `60-loadtest.sh` because it installs the full kube-prometheus-stack + runs k6 (heavy on a fresh
  machine). Run it explicitly, or `SKIP_STEPS="" ./scripts/run-all.sh` to run everything.

---

See also: `TROUBLESHOOTING.md` (Part 3), `MIGRATION-NOTES.md` (Part 4), `LOADTEST.md` (Part 6),
`OPS-ANSWERS.md` (Part 7), `AI-USAGE.md`.
