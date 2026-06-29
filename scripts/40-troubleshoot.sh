#!/usr/bin/env sh
set -eu
cd /workspace

echo ">> applying fixed troubleshoot manifests"
kubectl apply -f troubleshoot/fixed-app.yaml

echo ">> waiting for deployments to roll out"
kubectl rollout status deployment/web -n troubleshoot --timeout=120s
kubectl rollout status deployment/ai-inference -n troubleshoot --timeout=120s

echo ">> running verifier"
sh troubleshoot/verify.sh
