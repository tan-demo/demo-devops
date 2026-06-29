#!/usr/bin/env sh
set -eu

NS=quote-api
URL="${URL:-http://k3d-devops-serverlb/api/quote}"

SPOT_NODE=$(kubectl get nodes -l acme.io/capacity=spot -o jsonpath='{.items[0].metadata.name}')
echo ">> spot node to reclaim: $SPOT_NODE"
echo ">> placement before:"
for n in $(kubectl get pods -n "$NS" -l app.kubernetes.io/name=quote-api -o jsonpath='{.items[*].spec.nodeName}'); do
  kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/capacity}{"\n"}'
done | sort | uniq -c

echo ">> starting curl loop against the Ingress (proves the service keeps answering)"
( ok=0; fail=0; end=$(( $(date +%s) + 45 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    if curl -fsS --max-time 2 "$URL" >/dev/null 2>&1; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
    sleep 1
  done
  echo ">> curl loop result during drill: ok=$ok fail=$fail" ) &
LOOP=$!

echo ">> cordon + drain $SPOT_NODE"
kubectl cordon "$SPOT_NODE"
kubectl drain "$SPOT_NODE" --ignore-daemonsets --delete-emptydir-data --force --timeout=90s || true

echo ">> pods rescheduling:"
kubectl get pods -n "$NS" -o wide --no-headers | awk '{print $1, $3, $7}'
kubectl rollout status deployment/quote-api -n "$NS" --timeout=120s || true

wait "$LOOP"

echo ">> uncordon $SPOT_NODE"
kubectl uncordon "$SPOT_NODE"

echo ">> placement after (still >=1 on-demand, none Pending):"
for n in $(kubectl get pods -n "$NS" -l app.kubernetes.io/name=quote-api -o jsonpath='{.items[*].spec.nodeName}'); do
  kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/capacity}{"\n"}'
done | sort | uniq -c
