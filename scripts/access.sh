#!/usr/bin/env bash
set -eu

# Host helper: writes a host-usable kubeconfig (rewrites the in-cluster host) + prints ArgoCD login.
if [ -n "${TOOLBOX:-}" ]; then
  echo "access.sh is a host helper — run it on your machine, not inside the toolbox."
  exit 0
fi

. "$(dirname "$0")/_preflight.sh"
preflight_host || exit $?
require_toolbox_running || exit $?

cd "$(dirname "$0")/.."

KUBECONFIG_OUT="${KUBECONFIG_OUT:-$HOME/.kube/k3d-dev.yaml}"
mkdir -p "$(dirname "$KUBECONFIG_OUT")"

docker compose exec -T toolbox cat /kubeconfig/config \
  | sed 's/host.docker.internal/127.0.0.1/g' > "$KUBECONFIG_OUT"

ARGO_PW=$(docker compose exec -T toolbox sh -c \
  'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d' \
  2>/dev/null || true)

cat <<EOF

================= Local access =================
1) Cluster (host kubectl):
     export KUBECONFIG=$KUBECONFIG_OUT
     kubectl get nodes

2) App (already exposed):
     curl http://localhost:8080/api/quote

3) ArgoCD UI:
     export KUBECONFIG=$KUBECONFIG_OUT
     kubectl port-forward -n argocd svc/argocd-server 8081:443
     open https://localhost:8081     # accept the self-signed cert
     login: admin / ${ARGO_PW:-<not ready — run again once ArgoCD is up>}
================================================
EOF
