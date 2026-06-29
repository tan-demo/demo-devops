#!/usr/bin/env sh
set -eu

NS=argocd
REPO_URL="${REPO_URL:-https://github.com/tan-demo/demo-devops}"
cd /workspace

echo ">> ensuring ArgoCD is installed"
kubectl get ns "$NS" >/dev/null 2>&1 || sh scripts/10-install-argocd.sh

if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo ">> registering private repo credentials with ArgoCD (token provided)"
  kubectl create secret generic repo-demo-devops -n "$NS" \
    --from-literal=type=git \
    --from-literal=url="$REPO_URL" \
    --from-literal=username=git \
    --from-literal=password="$GITHUB_TOKEN" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
    | kubectl apply -f -
else
  echo ">> no GITHUB_TOKEN — assuming repo is public (no credentials needed)"
fi

echo ">> applying AppProject + applications-dev app-of-apps"
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applications-dev.yaml

echo ">> waiting for quote-api-dev Application to be created by applications-dev..."
i=0
until kubectl get application quote-api-dev -n "$NS" >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -gt 60 ] && { echo "applications-dev did not create quote-api-dev"; break; }
  sleep 3
done

# Nudge ArgoCD to reconcile now instead of waiting for the default interval.
kubectl annotate application quote-api-dev -n "$NS" \
  argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true

echo ">> waiting for ArgoCD to sync the chart (quote-api deployment to appear)..."
i=0
until kubectl get deployment quote-api -n quote-api >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -gt 100 ] && { echo "quote-api deployment was not created by ArgoCD in time"; break; }
  sleep 3
done

echo ">> waiting for quote-api to roll out..."
kubectl rollout status deployment/quote-api -n quote-api --timeout=180s || true

echo ">> waiting for quote-api-dev to be Synced + Healthy..."
i=0
until [ "$(kubectl get application quote-api-dev -n "$NS" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)" = "Synced/Healthy" ]; do
  i=$((i + 1)); [ "$i" -gt 40 ] && break
  sleep 3
done

echo ">> ArgoCD applications:"
kubectl get applications -n "$NS"
echo ">> quote-api pods:"
kubectl get pods -n quote-api -o wide 2>/dev/null || true
