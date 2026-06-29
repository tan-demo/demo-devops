#!/usr/bin/env sh
set -eu

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.4.4}"
NS=argocd

echo ">> installing ArgoCD ${ARGOCD_VERSION} into namespace '${NS}'"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n "$NS" -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo ">> waiting for ArgoCD core components to be ready..."
kubectl rollout status deployment/argocd-repo-server -n "$NS" --timeout=300s
kubectl rollout status deployment/argocd-server -n "$NS" --timeout=300s
kubectl rollout status statefulset/argocd-application-controller -n "$NS" --timeout=300s 2>/dev/null \
  || kubectl rollout status deployment/argocd-application-controller -n "$NS" --timeout=300s 2>/dev/null \
  || true

echo ">> ArgoCD ready."
