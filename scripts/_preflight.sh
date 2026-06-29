#!/usr/bin/env sh
# Sourced by host helpers (run-all.sh, access.sh, destroy.sh). PREFLIGHT_AUTO_INSTALL=0 = check-only.
# Targets the Golden Rule's shell: macOS / Linux / WSL2.

PREFLIGHT_AUTO_INSTALL="${PREFLIGHT_AUTO_INSTALL:-1}"
COMPOSE_PLUGIN_VERSION="${COMPOSE_PLUGIN_VERSION:-v2.32.4}"

_have() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Linux)
      if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then echo wsl; else echo linux; fi ;;
    Darwin) echo macos ;;
    *) echo unknown ;;
  esac
}

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
      if _have apt-get || _have dnf || _have yum; then curl -fsSL https://get.docker.com | _sudo "sh"; else return 1; fi ;;
    macos) _have brew && brew install --cask docker || return 1 ;;
    *) return 1 ;;
  esac
}

_install_compose_plugin() {
  [ "$PREFLIGHT_AUTO_INSTALL" = 1 ] || return 1
  case "$(uname -m)" in x86_64|amd64) a=x86_64 ;; aarch64|arm64) a=aarch64 ;; *) a="$(uname -m)" ;; esac
  o=linux; [ "$(uname -s)" = Darwin ] && o=darwin
  dst="$HOME/.docker/cli-plugins"; mkdir -p "$dst"
  echo ">> installing docker compose plugin $COMPOSE_PLUGIN_VERSION into $dst"
  curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_PLUGIN_VERSION}/docker-compose-${o}-${a}" \
    -o "$dst/docker-compose" && chmod +x "$dst/docker-compose"
}

_start_daemon() {
  echo ">> docker installed but daemon not reachable — trying to start it"
  case "$1" in
    macos) _have open && open -a Docker >/dev/null 2>&1 || true ;;
    linux|wsl) _sudo "systemctl start docker" 2>/dev/null || _sudo "service docker start" 2>/dev/null || true ;;
  esac
  i=0; while [ "$i" -lt 60 ]; do docker info >/dev/null 2>&1 && return 0; i=$((i + 1)); sleep 2; done
  return 1
}

preflight_host() {
  os="$(detect_os)"
  echo ">> host OS: $os ($(uname -srm 2>/dev/null))"
  [ "$os" = unknown ] && echo "WARN: unrecognised OS '$(uname -s)' — targets macOS/Linux/WSL2 (on Windows use WSL2)." >&2

  _have docker || _install_docker "$os" || true
  if ! _have docker; then
    echo "ERROR: 'docker' is not available — install it: https://docs.docker.com/get-docker/" >&2; return 127
  fi

  docker compose version >/dev/null 2>&1 || _install_compose_plugin || true
  if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: the Docker Compose v2 plugin is missing — https://docs.docker.com/compose/install/" >&2; return 127
  fi

  if ! docker info >/dev/null 2>&1; then
    _start_daemon "$os" || {
      echo "ERROR: the Docker daemon is not reachable and could not be started." >&2
      [ "$os" = macos ] && echo "   Start Docker Desktop and wait until it reports 'running'." >&2 \
                        || echo "   sudo systemctl start docker  (and add your user to the 'docker' group)." >&2
      return 1
    }
  fi

  echo ">> preflight OK: docker $(docker version -f '{{.Client.Version}}' 2>/dev/null), compose $(docker compose version --short 2>/dev/null)"
  return 0
}

require_toolbox_running() {
  if ! docker compose ps toolbox 2>/dev/null | grep -qiE 'running|[[:space:]]up'; then
    echo "ERROR: the 'toolbox' container is not running — run 'docker compose up -d' first." >&2
    return 1
  fi
  return 0
}

# The in-cluster tools live inside the toolbox image (baked by toolbox/Dockerfile), not on the host.
# Verify they're present; if not, the image is the source of truth, so the fix is a rebuild.
require_toolbox_tools() {
  miss=$(docker compose exec -T toolbox sh -c \
    'for t in kubectl helm terraform k6 k3d argocd jq yq git curl; do command -v "$t" >/dev/null 2>&1 || echo "$t"; done' 2>/dev/null)
  if [ -n "$miss" ]; then
    echo "ERROR: the toolbox image is missing:" $miss >&2
    echo "       rebuild it: docker compose build --no-cache toolbox" >&2
    return 1
  fi
  return 0
}
