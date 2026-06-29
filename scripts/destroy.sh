#!/usr/bin/env bash
set -eu

# Host helper: tear everything down (the inverse of `docker compose up -d` + run-all.sh).
# The k3d cluster runs as its own Docker containers (created by k3d inside the toolbox via the
# mounted docker socket), so `docker compose down` alone does NOT remove it — we delete the
# cluster first, then bring the toolbox + network down. Run it from your machine, not the toolbox.
if [ -n "${TOOLBOX:-}" ]; then
  echo "destroy.sh is a host helper — run it on your machine, not inside the toolbox."
  exit 0
fi

. "$(dirname "$0")/_preflight.sh"
preflight_host || exit $?

CLUSTER="${CLUSTER:-devops}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$HOME/.kube/k3d-devops.yaml}"

echo ">> deleting the k3d cluster '$CLUSTER' (via the toolbox, while it is still up)"
docker compose exec -T toolbox k3d cluster delete "$CLUSTER" 2>/dev/null || \
  echo "   (toolbox not running or cluster already gone — continuing)"

echo ">> stopping the toolbox + removing the compose network/volumes"
docker compose down -v --remove-orphans

echo ">> removing the host kubeconfig ($KUBECONFIG_OUT)"
rm -f "$KUBECONFIG_OUT"

echo ">> done. The toolbox image (demo-devops-toolbox:local) is kept for a fast re-up;"
echo "   run 'docker rmi demo-devops-toolbox:local' to remove it too."
