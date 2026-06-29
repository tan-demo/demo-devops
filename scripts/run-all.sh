#!/usr/bin/env bash
set -euo pipefail

# Runs every numbered step in order. Safe to re-run (each step is idempotent).
# On the host this re-execs inside the toolbox container (which has kubectl/helm/k6).
if [ -z "${TOOLBOX:-}" ]; then
  echo ">> not in toolbox — running all steps inside the toolbox container"
  rc=0
  docker compose exec -T toolbox /workspace/scripts/run-all.sh || rc=$?
  echo ""
  echo ">> setting up local access (host kubeconfig + ArgoCD login)..."
  sh "$(dirname "$0")/access.sh" || true
  exit "$rc"
fi

cd /workspace

# Step 25 (reclaim drill) runs by default — it is fast and self-heals (uncordons).
# Step 60 (load test) is opt-in: it installs the full kube-prometheus-stack and runs
# k6, which is heavy on a fresh machine. Override with SKIP_STEPS="" to run everything.
SKIP_STEPS="${SKIP_STEPS:-60}"

for step in scripts/[0-9][0-9]-*.sh; do
  [ -e "$step" ] || continue
  num=$(basename "$step" | cut -c1-2)
  case " $SKIP_STEPS " in
    *" $num "*) echo ">> skipping $step (run it individually)"; continue ;;
  esac
  echo ""
  echo "==================================================================="
  echo ">> $step"
  echo "==================================================================="
  sh "$step"
done

echo ""
echo ">> core steps complete (including the 25 reclaim drill)."
echo ">> load test (Part 6, opt-in — heavy): docker compose exec toolbox /workspace/scripts/60-loadtest.sh"
