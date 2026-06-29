#!/usr/bin/env bash
set -eu

# Host helper: makes the cluster reachable from the host and prints ArgoCD login.
if [ -n "${TOOLBOX:-}" ]; then
  echo "access.sh is a host helper — run it on your machine, not inside the toolbox."
  exit 0
fi

. "$(dirname "$0")/_preflight.sh"
preflight_host || exit $?
require_toolbox_running || exit $?

cd "$(dirname "$0")/.."

CTX=k3d-dev

ARGO_PW=$(docker compose exec -T toolbox sh -c \
  'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d' \
  2>/dev/null || true)

HOST_LINE="install kubectl on your host to use it directly — the toolbox option above needs nothing."
if command -v kubectl >/dev/null 2>&1; then
  mkdir -p "$HOME/.kube"
  prev_ctx=$(kubectl config current-context 2>/dev/null || true)
  tmp=$(mktemp)
  # k3d kubeconfig get returns a host-reachable server; the in-cluster /kubeconfig/config points at
  # k3d-dev-serverlb, which only resolves inside the docker network.
  docker compose exec -T toolbox k3d kubeconfig get dev 2>/dev/null \
    | sed -e 's#https://0\.0\.0\.0:#https://127.0.0.1:#' -e 's#https://host\.docker\.internal:#https://127.0.0.1:#' > "$tmp"
  KUBECONFIG="$HOME/.kube/config:$tmp" kubectl config view --flatten > "$HOME/.kube/config.tmp.$$"
  mv "$HOME/.kube/config.tmp.$$" "$HOME/.kube/config"
  rm -f "$tmp"
  # k3d-dev as current context (its embedded CA avoids the macOS-keychain x509 error on other contexts).
  kubectl config use-context "$CTX" >/dev/null 2>&1 || true
  HOST_LINE="merged into ~/.kube/config and set current (was: ${prev_ctx:-none} — \`kubectl config use-context ${prev_ctx:-…}\` to switch back):
       kubectl get nodes"
fi

cat <<EOF

================= Local access =================
1) Cluster:
   - via the toolbox (always works, no host tools needed):
       docker compose exec toolbox kubectl get nodes
   - from your host: $HOST_LINE

2) App (exposed on the host):
       curl http://localhost:8080/api/quote

3) ArgoCD UI (needs host kubectl):
       kubectl --context $CTX port-forward -n argocd svc/argocd-server 8081:443
       open https://localhost:8081     # accept the self-signed cert
       login: admin / ${ARGO_PW:-<not ready — run scripts/access.sh again once ArgoCD is up>}
================================================
EOF
