#!/usr/bin/env sh
set -eu
cd /workspace

echo ">> applying the BROKEN manifests (the incident handoff we were given)"
kubectl apply -f troubleshoot/broken-app.yaml

echo ">> observing the broken state (pods will not reach Ready — wrong configmap ref,"
echo "   bad taint/affinity, default-deny with no egress; see TROUBLESHOOTING.md):"
kubectl get pods -n troubleshoot 2>/dev/null || true

echo ">> applying the diagnosed fix"
kubectl apply -f troubleshoot/fixed-app.yaml

echo ">> waiting for deployments to roll out"
kubectl rollout status deployment/web -n troubleshoot --timeout=120s
kubectl rollout status deployment/ai-inference -n troubleshoot --timeout=120s

echo ">> running verifier"
sh troubleshoot/verify.sh
