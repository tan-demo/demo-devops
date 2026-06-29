#!/usr/bin/env bash
set -eu

# Host teardown. k3d runs as its own containers, so we delete the cluster before `compose down`.
if [ -n "${TOOLBOX:-}" ]; then
  echo "destroy.sh is a host helper — run it on your machine, not inside the toolbox."
  exit 0
fi

. "$(dirname "$0")/_preflight.sh"
preflight_host || exit $?

CLUSTER="${CLUSTER:-dev}"

echo ">> deleting the k3d cluster '$CLUSTER' (via the toolbox, while it is still up)"
docker compose exec -T toolbox k3d cluster delete "$CLUSTER" 2>/dev/null || \
  echo "   (toolbox not running or cluster already gone — continuing)"

echo ">> stopping the toolbox + removing the compose network/volumes"
docker compose down -v --remove-orphans

echo ">> removing the k3d-$CLUSTER context from ~/.kube/config"
if command -v kubectl >/dev/null 2>&1; then
  [ "$(kubectl config current-context 2>/dev/null)" = "k3d-$CLUSTER" ] && kubectl config unset current-context >/dev/null 2>&1 || true
  kubectl config delete-context "k3d-$CLUSTER" 2>/dev/null || true
  kubectl config delete-cluster "k3d-$CLUSTER" 2>/dev/null || true
  kubectl config delete-user "admin@k3d-$CLUSTER" 2>/dev/null || true
fi
rm -f "$HOME/.kube/k3d-$CLUSTER.yaml"

APP_IMAGE="${IMAGE:-ghcr.io/tan-demo/quote-api}:${TAG:-dev}"
echo ">> removing the app image built by run-all ($APP_IMAGE)"
docker rmi "$APP_IMAGE" 2>/dev/null || true

if [ "${FULL:-0}" = 1 ]; then
  echo ">> FULL=1 — removing the toolbox image too"
  docker rmi demo-devops-toolbox:local 2>/dev/null || true
  echo ">> done — everything created by the harness is gone."
else
  echo ">> done. The toolbox image (demo-devops-toolbox:local) is kept for a fast re-up;"
  echo "   run 'FULL=1 ./scripts/destroy.sh' (or 'docker rmi demo-devops-toolbox:local') to remove it too."
fi
