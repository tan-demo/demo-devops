#!/usr/bin/env bash
set -euo pipefail

CLUSTER=dev
CONFIG=/workspace/toolbox/k3d-config.yaml
KUBE=/kubeconfig/config

log() { echo "[bootstrap] $*"; }

if k3d cluster list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$CLUSTER"; then
  log "cluster '$CLUSTER' already exists — skipping create (idempotent)"
else
  log "creating k3d cluster '$CLUSTER' (1 server + 4 agents)..."
  k3d cluster create --config "$CONFIG"
fi

log "writing in-network kubeconfig to $KUBE"
mkdir -p "$(dirname "$KUBE")"
k3d kubeconfig get "$CLUSTER" > "$KUBE"
sed -i "s#server: https://0.0.0.0:[0-9]*#server: https://k3d-${CLUSTER}-serverlb:6443#" "$KUBE"
sed -i "s#server: https://127.0.0.1:[0-9]*#server: https://k3d-${CLUSTER}-serverlb:6443#" "$KUBE"
export KUBECONFIG="$KUBE"

log "waiting for nodes to be Ready..."
for _ in $(seq 1 60); do
  if kubectl get nodes 2>/dev/null | grep -q ' Ready'; then break; fi
  sleep 2
done
kubectl wait --for=condition=Ready nodes --all --timeout=120s

log "running troubleshoot/prepare.sh (labels + taints, idempotent)..."
sh /workspace/troubleshoot/prepare.sh

log "DONE — cluster ready. Toolbox staying up."
kubectl get nodes -L acme.io/capacity -L acme.io/node-type || true
touch /kubeconfig/bootstrap.done

tail -f /dev/null
