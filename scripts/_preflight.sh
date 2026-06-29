#!/usr/bin/env sh
# Sourced by host helpers (run-all.sh, access.sh, destroy.sh). PREFLIGHT_AUTO_INSTALL=0 = check-only.

# Git Bash (MSYS) would rewrite /workspace and /kubeconfig args to `docker compose exec` into
# Windows paths; keep them literal. No-op on Linux/macOS/WSL.
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
        curl -fsSL https://get.docker.com | _sudo "sh"
      else return 1; fi ;;
    macos)  _have brew  && brew install --cask docker || return 1 ;;
    windows) _have winget && winget install -e --id Docker.DockerDesktop || return 1 ;;
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

# Start Docker Desktop on Windows WITHOUT hardcoding its install path (Program Files, drive
# letter, locale and per-user installs all vary). preflight already verified `docker` is on
# PATH, so the official `docker desktop` CLI (Docker Desktop 4.37+) is the most reliable, fully
# path-agnostic trigger. Older Docker Desktop lacks that CLI, so fall back to locating the exe
# relative to the docker binary (<root>/resources/bin/docker -> <root>/Docker Desktop.exe), then
# the registry install path. Best-effort throughout — the caller still polls `docker info`.
_start_docker_desktop_win() {
  docker desktop start >/dev/null 2>&1 && return 0
  _exe=""
  _d="$(command -v docker 2>/dev/null)"
  if [ -n "$_d" ]; then
    _c="$(dirname "$(dirname "$(dirname "$_d")")")/Docker Desktop.exe"
    [ -f "$_c" ] && _exe="$_c"
  fi
  if [ -z "$_exe" ] && _have powershell; then
    _reg="$(powershell -NoProfile -Command "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Docker Inc.\\Docker\\1.0' -EA SilentlyContinue).AppPath" 2>/dev/null | tr -d '\r')"
    [ -n "$_reg" ] && [ -f "$_reg/Docker Desktop.exe" ] && _exe="$_reg/Docker Desktop.exe"
  fi
  [ -n "$_exe" ] && _have powershell && powershell -NoProfile -Command "Start-Process '$_exe'" >/dev/null 2>&1 || true
}

_start_daemon() {
  os="$1"
  echo ">> docker installed but daemon not reachable — trying to start it"
  case "$os" in
    macos) _have open && open -a Docker >/dev/null 2>&1 || true ;;
    linux|wsl) _sudo "systemctl start docker" 2>/dev/null || _sudo "service docker start" 2>/dev/null || true ;;
    windows) _start_docker_desktop_win ;;
  esac
  i=0; while [ "$i" -lt 60 ]; do docker info >/dev/null 2>&1 && return 0; i=$((i + 1)); sleep 2; done
  return 1
}

_docker_install_help() {
  case "$1" in
    linux|wsl) echo "   Linux: curl -fsSL https://get.docker.com | sh   (https://docs.docker.com/engine/install/)" >&2 ;;
    macos)     echo "   macOS: brew install --cask docker, then launch Docker Desktop (https://docs.docker.com/desktop/install/mac-install/)" >&2 ;;
    windows)   echo "   Windows: winget install Docker.DockerDesktop — run these scripts from WSL2 or Git Bash" >&2 ;;
    *)         echo "   See https://docs.docker.com/get-docker/" >&2 ;;
  esac
}

preflight_host() {
  os="$(detect_os)"
  echo ">> host OS: $os ($(uname -srm 2>/dev/null))"
  [ "$os" = unknown ] && echo "WARN: unrecognised OS '$(uname -s)' — targets Linux, WSL2, macOS, Windows Git Bash." >&2

  _have docker || _install_docker "$os" || true
  if ! _have docker; then
    echo "ERROR: 'docker' is not available." >&2; _docker_install_help "$os"; return 127
  fi

  docker compose version >/dev/null 2>&1 || _install_compose_plugin || true
  if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: the Docker Compose v2 plugin is missing — https://docs.docker.com/compose/install/" >&2; return 127
  fi

  if ! docker info >/dev/null 2>&1; then
    _start_daemon "$os" || {
      echo "ERROR: the Docker daemon is not reachable and could not be started." >&2
      case "$os" in
        macos)   echo "   Start Docker Desktop and wait until it reports 'running'." >&2 ;;
        windows) echo "   Start Docker Desktop; run these scripts from WSL2 or Git Bash." >&2 ;;
        *)       echo "   sudo systemctl start docker  (and add your user to the 'docker' group)." >&2 ;;
      esac
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
