#!/usr/bin/env bash
set -euo pipefail

# Runs every numbered step in order. Safe to re-run (each step is idempotent).
# On the host this re-execs inside the toolbox container (which has kubectl/helm/k6).
if [ -z "${TOOLBOX:-}" ]; then
  echo ">> not in toolbox — re-exec inside the toolbox container"
  exec docker compose exec -T toolbox /workspace/scripts/run-all.sh
fi

cd /workspace

# Heavy/disruptive demos are opt-in (run them individually). Override with SKIP_STEPS="".
SKIP_STEPS="${SKIP_STEPS:-25 60}"

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
echo ">> core steps complete."
echo ">> resilience demo:  docker compose exec toolbox /workspace/scripts/25-reclaim-drill.sh"
echo ">> load test (Part 6): docker compose exec toolbox /workspace/scripts/60-loadtest.sh"
