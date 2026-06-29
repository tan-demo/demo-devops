# Part 3 — Troubleshooting Write-up

`troubleshoot/broken-app.yaml` was broken in **7 independent ways**. Below: symptom,
the exact commands used to diagnose, the root cause, and the fix. Fixed manifests are
in `troubleshoot/fixed-app.yaml`; `troubleshoot/verify.sh` prints `PASS`.

Rules honored: the `default-deny` NetworkPolicy is **kept** (least-privilege allow rules
added instead of deleting it); node labels/taints are **untouched** (workloads fixed,
not nodes).

---

## How I approached it

```bash
kubectl apply -f troubleshoot/broken-app.yaml
kubectl get pods -n troubleshoot -o wide
kubectl get events -n troubleshoot --sort-by=.lastTimestamp
```

Pods were a mix of `Pending`, `CrashLoopBackOff`/`Running but NotReady`, and the Service
had no endpoints. Each symptom traced to a separate root cause.

---

## Issue 1 — `web` pods Pending: impossible memory request

- **Symptom:** `web` pods stuck `Pending`.
- **Diagnose:**
  ```bash
  kubectl describe pod -n troubleshoot -l app=web | grep -A3 Events
  # FailedScheduling: 0/5 nodes are available: Insufficient memory
  ```
- **Root cause:** `resources.requests.memory: 16Gi` (and limit `16Gi`) — no node has 16Gi.
- **Fix:** sane values — requests `32Mi`, limits `64Mi`.

## Issue 2 — `web` image does not exist

- **Symptom:** `ErrImagePull` / `ImagePullBackOff` once scheduling was possible.
- **Diagnose:**
  ```bash
  kubectl describe pod -n troubleshoot -l app=web | grep -i image
  # Failed to pull image "nginx:1.25.99": not found
  ```
- **Root cause:** tag `nginx:1.25.99` is not a real nginx tag.
- **Fix:** `nginx:1.25`.

## Issue 3 — liveness/readiness probes on the wrong port

- **Symptom:** container restarts / never becomes Ready.
- **Diagnose:**
  ```bash
  kubectl describe pod -n troubleshoot -l app=web | grep -iE "probe|Unhealthy"
  # Liveness probe failed: connection refused on 8080
  ```
- **Root cause:** probes target port `8080`, but nginx listens on `80`.
- **Fix:** probes `httpGet.port: 80`.

## Issue 4 — wrong ConfigMap name in the volume

- **Symptom:** even with a valid image, the page is empty / default nginx, not `TROUBLESHOOT-OK`.
- **Diagnose:**
  ```bash
  kubectl describe pod -n troubleshoot -l app=web | grep -iE "configmap|volume"
  # configmap "web-conf" not found
  ```
- **Root cause:** the volume references ConfigMap `web-conf`, but the actual ConfigMap is `web-config`.
- **Fix:** `volumes[].configMap.name: web-config`.

## Issue 5 — Service selector + targetPort mismatch (no endpoints)

- **Symptom:** `web-svc` has no endpoints; nothing reachable through the Service.
- **Diagnose:**
  ```bash
  kubectl get endpoints web-svc -n troubleshoot
  # ENDPOINTS: <none>
  kubectl get svc web-svc -n troubleshoot -o jsonpath='{.spec.selector}{"\n"}{.spec.ports}'
  ```
- **Root cause:** selector `app: webapp` matches no pod (`app: web`); `targetPort: 8080` is wrong (nginx is `80`).
- **Fix:** selector `app: web`, `targetPort: 80`.

## Issue 6 — `ai-inference` Pending: wrong nodeSelector + missing toleration

- **Symptom:** `ai-inference` stuck `Pending`; must run on the GPU node.
- **Diagnose:**
  ```bash
  kubectl describe pod -n troubleshoot -l app=ai-inference | grep -A3 Events
  # 0/5 nodes available: node(s) didn't match node selector / had untolerated taint nvidia.com/gpu
  kubectl get nodes -L acme.io/node-type
  ```
- **Root cause:** two issues — `nodeSelector: node-type=gpu` (real label is `acme.io/node-type=gpu`),
  and no toleration for the GPU node taint `nvidia.com/gpu=true:NoSchedule`.
- **Fix:** `nodeSelector: acme.io/node-type: gpu` **plus** a matching toleration. Node taint left untouched.

## Issue 7 — default-deny NetworkPolicy blocks the smoke test (DNS + traffic)

- **Symptom:** in-cluster smoke test fails; the curl Job cannot reach `web-svc`.
- **Diagnose:**
  ```bash
  kubectl logs job/smoke-test -n troubleshoot
  # could not resolve host / connection timed out
  kubectl get networkpolicy -n troubleshoot
  ```
- **Root cause:** `default-deny` (podSelector `{}`, Ingress+Egress) denies **all** traffic,
  including DNS resolution and the smoke-client → web path.
- **Fix (least-privilege, default-deny kept):** add three allow policies —
  - `allow-dns`: egress to `kube-system` on UDP/TCP 53 (so names resolve),
  - `allow-web-from-smoke`: ingress to `app=web` from `app=smoke-client` on TCP 80,
  - `allow-smoke-to-web`: egress from `app=smoke-client` to `app=web` on TCP 80.

---

## Result

```bash
sh troubleshoot/verify.sh
# [1/7] ... [7/7] In-cluster smoke test through the Service...
# PASS
```
