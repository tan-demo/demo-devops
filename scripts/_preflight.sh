#!/usr/bin/env sh
# Host-side preflight, sourced by the host helpers (run-all.sh, access.sh, destroy.sh).
# The only thing this project needs on the host is Docker + the Compose v2 plugin —
# every other tool (kubectl/helm/terraform/k6/k3d/argocd) lives inside the toolbox image.
# We check that up front so a missing/stopped Docker fails with a clear, actionable message
# instead of a cryptic error deep inside a step.

preflight_host() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: 'docker' is not installed or not on your PATH." >&2
    echo "       Everything else runs inside the toolbox container; only Docker + the" >&2
    echo "       Compose v2 plugin are needed on the host." >&2
    echo "       Install: https://docs.docker.com/get-docker/" >&2
    return 127
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: the Docker Compose v2 plugin ('docker compose') is missing." >&2
    echo "       Update Docker Desktop, or install it: https://docs.docker.com/compose/install/" >&2
    echo "       (the legacy 'docker-compose' v1 binary is not used here)" >&2
    return 127
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: the Docker daemon is not reachable (not running, or permission denied)." >&2
    echo "       macOS/Windows: start Docker Desktop and wait until it reports 'running'." >&2
    echo "       Linux: sudo systemctl start docker  (and add your user to the 'docker' group)." >&2
    return 1
  fi
  return 0
}

require_toolbox_running() {
  if ! docker compose ps toolbox 2>/dev/null | grep -qiE 'running|[[:space:]]up'; then
    echo "ERROR: the 'toolbox' container is not running." >&2
    echo "       Bring the harness up first (this also creates the k3d cluster):" >&2
    echo "         docker compose up -d" >&2
    return 1
  fi
  return 0
}
