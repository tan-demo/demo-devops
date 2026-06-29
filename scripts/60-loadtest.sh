#!/usr/bin/env sh
set -eu
cd /workspace

MON_NS=monitoring
APP_NS=quote-api
BASE_URL="${BASE_URL:-http://k3d-devops-serverlb}"

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

echo ">> HPA before load:"
kubectl get hpa -n "$APP_NS"

echo ">> running k6 load test through the Ingress ($BASE_URL)"
BASE_URL="$BASE_URL" k6 run loadtest/script.js || true

echo ">> HPA after load (expect replicas scaled beyond 3):"
kubectl get hpa -n "$APP_NS"
echo ">> placement of replicas (new ones still respect spot/on-demand):"
for n in $(kubectl get pods -n "$APP_NS" -l app.kubernetes.io/name=quote-api -o jsonpath='{.items[*].spec.nodeName}'); do
  kubectl get node "$n" -o jsonpath='{.metadata.labels.acme\.io/capacity}{"\n"}'
done | sort | uniq -c
