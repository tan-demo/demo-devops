#!/usr/bin/env sh
# Host-side preflight, sourced by the host helpers (run-all.sh, access.sh, destroy.sh).
#
# The only host dependency is Docker + the Compose v2 plugin — every other tool
# (kubectl/helm/terraform/k6/k3d/argocd) lives inside the toolbox image. This script:
#   1. detects the host OS via `uname` (Linux / WSL / macOS / Windows-Git-Bash),
#   2. AUTO-INSTALLS what is safe to (the Compose v2 plugin user-local; Docker via the
#      platform's own package manager when present),
#   3. starts the Docker daemon if it is installed but not running,
#   4. if everything is already there, just continues.
#
# Auto-install is best-effort and transparent (it prints what it runs). Disable it with
# PREFLIGHT_AUTO_INSTALL=0 to get check-only behaviour. Where a step genuinely cannot be
# automated from a shell (macOS/Windows Docker Desktop is a licensed GUI app), it falls
# back to precise per-OS instructions instead of failing cryptically.

# Windows Git Bash (MSYS) rewrites /unix/paths in command arguments into Windows paths, which
# would mangle `docker compose exec -T toolbox /workspace/...` and `/kubeconfig/...`. Disable that
# for the host scripts that source this file. Harmless no-op on Linux/macOS/WSL.
MSYS_NO_PATHCONV=1; export MSYS_NO_PATHCONV
MSYS2_ARG_CONV_EXCL='*'; export MSYS2_ARG_CONV_EXCL

PREFLIGHT_AUTO_INSTALL="${PREFLIGHT_AUTO_INSTALL:-1}"
COMPOSE_PLUGIN_VERSION="${COMPOSE_PLUGIN_VERSION:-v2.32.4}"

_have() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Linux)
      if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then echo wsl; else echo linux; fi ;;
    Darwin) echo macos ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}

# sudo only if we are not already root and sudo exists; otherwise empty (commands run as-is)
_sudo() {
  if [ "$(id -u 2>/dev/null || echo 0)" = 0 ]; then sh -c "$*"; elif _have sudo; then sudo sh -c "$*"; else
    echo "   (need root for: $*  — re-run as root or install sudo)" >&2; return 1; fi
}

_install_docker() {
  os="$1"
  [ "$PREFLIGHT_AUTO_INSTALL" = 1 ] || return 1
  echo ">> docker not found — attempting install for '$os' (PREFLIGHT_AUTO_INSTALL=0 to skip)"
  case "$os" in
    linux|wsl)
      if _have apt-get || _have dnf || _have yum; then
        echo "   running the official get.docker.com convenience script"
        curl -fsSL https://get.docker.com | _sudo "sh"
      else return 1; fi ;;
    macos)
      if _have brew; then echo "   brew install --cask docker"; brew install --cask docker; else return 1; fi ;;
    windows)
      if _have winget; then echo "   winget install Docker.DockerDesktop"; winget install -e --id Docker.DockerDesktop; else return 1; fi ;;
    *) return 1 ;;
  esac
}

_install_compose_plugin() {
  [ "$PREFLIGHT_AUTO_INSTALL" = 1 ] || return 1
  case "$(uname -m)" in x86_64|amd64) a=x86_64 ;; aarch64|arm64) a=aarch64 ;; *) a="$(uname -m)" ;; esac
  o=linux; [ "$(uname -s)" = Darwin ] && o=darwin
  dst="$HOME/.docker/cli-plugins"; mkdir -p "$dst"
  echo ">> installing the docker compose plugin ($COMPOSE_PLUGIN_VERSION) into $dst (user-local, no sudo)"
  curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_PLUGIN_VERSION}/docker-compose-${o}-${a}" \
    -o "$dst/docker-compose" && chmod +x "$dst/docker-compose"
}

_start_daemon() {
  os="$1"
  echo ">> docker is installed but the daemon is not reachable — trying to start it"
  case "$os" in
    macos) _have open && open -a Docker >/dev/null 2>&1 || true ;;
    linux|wsl) _sudo "systemctl start docker" 2>/dev/null || _sudo "service docker start" 2>/dev/null || true ;;
    windows) _have powershell && powershell -Command "Start-Process 'Docker Desktop'" >/dev/null 2>&1 || true ;;
  esac
  i=0; while [ "$i" -lt 60 ]; do docker info >/dev/null 2>&1 && return 0; i=$((i + 1)); sleep 2; done
  return 1
}

_docker_install_help() {
  case "$1" in
    linux|wsl) echo "   Linux: curl -fsSL https://get.docker.com | sh   (see https://docs.docker.com/engine/install/)" >&2 ;;
    macos) echo "   macOS: brew install --cask docker   then launch Docker Desktop (https://docs.docker.com/desktop/install/mac-install/)" >&2 ;;
    windows) echo "   Windows: winget install Docker.DockerDesktop  — and use WSL2 or Git Bash to run these scripts" >&2 ;;
    *) echo "   See https://docs.docker.com/get-docker/" >&2 ;;
  esac
}

preflight_host() {
  os="$(detect_os)"
  echo ">> host OS: $os ($(uname -srm 2>/dev/null))"
  if [ "$os" = unknown ]; then
    echo "WARN: unrecognised OS '$(uname -s)'. These scripts target Linux, WSL2, macOS, or Windows Git Bash." >&2
  fi

  if ! _have docker; then
    _install_docker "$os" || true
  fi
  if ! _have docker; then
    echo "ERROR: 'docker' is still not available." >&2
    _docker_install_help "$os"
    return 127
  fi

  if ! docker compose version >/dev/null 2>&1; then
    _install_compose_plugin || true
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: the Docker Compose v2 plugin ('docker compose') is missing and could not be installed." >&2
    echo "   Install it: https://docs.docker.com/compose/install/" >&2
    return 127
  fi

  if ! docker info >/dev/null 2>&1; then
    _start_daemon "$os" || {
      echo "ERROR: the Docker daemon is not reachable and could not be started automatically." >&2
      case "$os" in
        macos) echo "   Start Docker Desktop and wait until it reports 'running'." >&2 ;;
        windows) echo "   Start Docker Desktop; run these scripts from WSL2 or Git Bash." >&2 ;;
        *) echo "   sudo systemctl start docker  (and add your user to the 'docker' group)." >&2 ;;
      esac
      return 1
    }
  fi

  echo ">> preflight OK: docker $(docker version -f '{{.Client.Version}}' 2>/dev/null), compose $(docker compose version --short 2>/dev/null)"
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
