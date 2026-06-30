#!/usr/bin/env sh
set -eu

NS=quote-api
URL="${URL:-http://k3d-dev-serverlb/api/quote}"
APP_LABEL=app.kubernetes.io/name=quote-api

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cleanup() {
  if [ -n "${LOOP:-}" ]; then
    kill "$LOOP" >/dev/null 2>&1 || true
    wait "$LOOP" >/dev/null 2>&1 || true
  fi
  if [ -n "${SPOT_NODE:-}" ]; then
    kubectl uncordon "$SPOT_NODE" >/dev/null 2>&1 || true
  fi
  if [ -n "${RESULTS:-}" ] && [ -f "$RESULTS" ]; then
    rm -f "$RESULTS"
  fi
}
trap cleanup EXIT INT TERM

print_placement() {
  for n in $(kubectl get pods -n "$NS" -l "$APP_LABEL" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}'); do
    kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/capacity}{"\n"}'
  done | sort | uniq -c
}

pod_nodes() {
  kubectl get pods -n "$NS" -l "$APP_LABEL" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}'
}

kubectl rollout status deployment/quote-api -n "$NS" --timeout=120s

SPOT_NODE=""
for n in $(pod_nodes | sort -u); do
  cap=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/capacity}')
  if [ "$cap" = "spot" ]; then
    SPOT_NODE="$n"
    break
  fi
done

[ -n "$SPOT_NODE" ] || fail "no quote-api pod is currently running on a spot node"

echo ">> spot node to reclaim: $SPOT_NODE"
echo ">> quote-api pods on reclaimed node:"
kubectl get pods -n "$NS" -l "$APP_LABEL" --field-selector "spec.nodeName=$SPOT_NODE" -o wide
echo ">> placement before:"
print_placement

echo ">> starting curl loop against the Ingress (proves the service keeps answering)"
RESULTS=$(mktemp)
( ok=0; fail=0; end=$(( $(date +%s) + 45 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    if curl -fsS --max-time 2 "$URL" >/dev/null 2>&1; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
    sleep 1
  done
  echo "$ok $fail" > "$RESULTS"
  echo ">> curl loop result during drill: ok=$ok fail=$fail" ) &
LOOP=$!

echo ">> cordon + drain $SPOT_NODE"
kubectl cordon "$SPOT_NODE"
kubectl drain "$SPOT_NODE" --ignore-daemonsets --delete-emptydir-data --force --timeout=90s

echo ">> pods rescheduling:"
kubectl get pods -n "$NS" -o wide --no-headers | awk '{print $1, $3, $7}'
kubectl rollout status deployment/quote-api -n "$NS" --timeout=120s

wait "$LOOP"
read ok fail_count < "$RESULTS"
[ "$ok" -gt 0 ] || fail "curl loop did not record any successful request"
[ "$fail_count" -eq 0 ] || fail "service returned $fail_count failed request(s) during spot drain"

echo ">> uncordon $SPOT_NODE"
kubectl uncordon "$SPOT_NODE"

echo ">> placement after (still >=1 on-demand, none Pending):"
print_placement

pending=$(kubectl get pods -n "$NS" -l "$APP_LABEL" -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | grep -c '^Pending$' || true)
[ "$pending" -eq 0 ] || fail "$pending quote-api pod(s) are still Pending after reclaim"

caps=$(for n in $(pod_nodes); do kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/capacity}{"\n"}'; done)
od_count=$(printf "%s\n" "$caps" | grep -c '^on-demand$' || true)
spot_count=$(printf "%s\n" "$caps" | grep -c '^spot$' || true)
[ "$od_count" -ge 1 ] || fail "expected at least one quote-api pod on on-demand after reclaim"
[ "$spot_count" -ge 1 ] || fail "expected at least one quote-api pod on spot after reclaim"

for n in $(pod_nodes); do
  cap=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/capacity}')
  node_type=$(kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/node-type}')
  case "$cap" in
    spot|on-demand) ;;
    *) fail "quote-api pod landed on node '$n' outside the spot/on-demand pool" ;;
  esac
  [ "$node_type" != "gpu" ] || fail "quote-api pod landed on GPU node '$n'"
done

echo ">> reclaim drill PASS: drained a spot node that hosted quote-api, service stayed up, placement survived."
