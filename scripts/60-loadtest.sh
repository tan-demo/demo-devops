#!/usr/bin/env sh
set -eu
cd /workspace

MON_NS=monitoring
APP_NS=quote-api
BASE_URL="${BASE_URL:-http://k3d-devops-serverlb}"
EVIDENCE_DIR=loadtest/evidence
HPA_LOG="$EVIDENCE_DIR/hpa-scale-out.log"
EVENTS_LOG="$EVIDENCE_DIR/pod-events.log"

echo ">> installing kube-prometheus-stack (Prometheus + Grafana)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n "$MON_NS" --create-namespace \
  --set grafana.sidecar.dashboards.enabled=true \
  --wait --timeout 10m

echo ">> enabling app monitoring CRs (ServiceMonitor + PrometheusRule)"
helm template qa charts/quote-api -n "$APP_NS" --set monitoring.enabled=true \
  -s templates/servicemonitor.yaml -s templates/prometheusrule.yaml \
  | kubectl apply -n "$APP_NS" -f -

echo ">> importing Grafana dashboard (from loadtest/dashboard.json)"
kubectl create configmap quote-api-dashboard -n "$MON_NS" \
  --from-file=quote-api.json=loadtest/dashboard.json \
  --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml \
  | kubectl apply -f -

mkdir -p "$EVIDENCE_DIR"
: > "$HPA_LOG"
: > "$EVENTS_LOG"

echo ">> HPA before load:"
kubectl get hpa -n "$APP_NS" | tee -a "$HPA_LOG"

echo ">> capturing HPA + pod events during load (see $EVIDENCE_DIR/)"
kubectl get hpa -n "$APP_NS" -w >> "$HPA_LOG" &
HPA_PID=$!
kubectl get events -n "$APP_NS" --watch-only \
  -o custom-columns=TIME:.lastTimestamp,TYPE:.type,REASON:.reason,OBJECT:.involvedObject.name,MESSAGE:.message \
  >> "$EVENTS_LOG" &
EVENTS_PID=$!

cleanup_watchers() {
  kill "$HPA_PID" "$EVENTS_PID" >/dev/null 2>&1 || true
  wait "$HPA_PID" >/dev/null 2>&1 || true
  wait "$EVENTS_PID" >/dev/null 2>&1 || true
}
trap cleanup_watchers EXIT INT TERM

echo ">> running k6 load test through the Ingress ($BASE_URL)"
k6_rc=0
BASE_URL="$BASE_URL" k6 run loadtest/script.js || k6_rc=$?

cleanup_watchers
trap - EXIT INT TERM

echo ">> HPA after load (expect replicas scaled beyond 3):"
kubectl get hpa -n "$APP_NS" | tee -a "$HPA_LOG"
echo ">> placement of replicas (new ones still respect spot/on-demand):"
for n in $(kubectl get pods -n "$APP_NS" -l app.kubernetes.io/name=quote-api -o jsonpath='{.items[*].spec.nodeName}'); do
  kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/capacity}{"\n"}'
done | sort | uniq -c

max_replicas=$(awk 'NR>1 {print $(NF-1)}' "$HPA_LOG" | sort -n | tail -1)
if [ -n "$max_replicas" ] && [ "$max_replicas" -le 3 ] 2>/dev/null; then
  echo ">> FAIL: HPA did not scale beyond 3 (max replicas seen: $max_replicas)" >&2
  exit 1
fi

if [ "$k6_rc" -ne 0 ]; then
  echo ">> FAIL: k6 thresholds not met (exit $k6_rc) — load test did not meet its SLOs" >&2
  exit "$k6_rc"
fi
echo ">> k6 thresholds passed."
echo ">> HPA scale-out evidence: $HPA_LOG"
echo ">> pod events evidence: $EVENTS_LOG"
