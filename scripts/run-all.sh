#!/usr/bin/env bash
set -euo pipefail

# Runs the numbered steps (idempotent). On the host, re-execs inside the toolbox container.
wait_for_bootstrap() {
  echo ">> waiting for k3d bootstrap (first boot may take a few minutes)..."
  i=0
  while [ "$i" -lt 120 ]; do
    if docker compose exec -T toolbox test -f /kubeconfig/bootstrap.done 2>/dev/null; then
      echo ">> cluster bootstrap complete"
      return 0
    fi
    i=$((i + 1))
    sleep 5
  done
  echo "FAIL: cluster bootstrap did not finish within 10 minutes" >&2
  echo "       check: docker compose logs toolbox" >&2
  return 1
}

if [ -z "${TOOLBOX:-}" ]; then
  . "$(dirname "$0")/_preflight.sh"
  preflight_host || exit $?
  require_toolbox_running || exit $?
  require_toolbox_tools || exit $?
  echo ">> not in toolbox — running all steps inside the toolbox container"
  wait_for_bootstrap
  rc=0
  docker compose exec -T -e SKIP_STEPS="${SKIP_STEPS-60}" toolbox /workspace/scripts/run-all.sh || rc=$?
  echo ""
  echo ">> setting up local access (host kubeconfig + ArgoCD login)..."
  sh "$(dirname "$0")/access.sh" || true
  exit "$rc"
fi

cd /workspace

# 60 (load test) is opt-in — heavy. SKIP_STEPS="" runs everything.
SKIP_STEPS="${SKIP_STEPS-60}"

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
echo ">> Part 6 (load test — not in default run-all): docker compose exec toolbox /workspace/scripts/60-loadtest.sh"
echo ">> or run everything: SKIP_STEPS= ./scripts/run-all.sh"
