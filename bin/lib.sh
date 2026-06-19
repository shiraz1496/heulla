#!/usr/bin/env bash
# Shared helpers for the project scripts. Sourced by setup.sh / deploy.sh / dev.sh.

set -euo pipefail

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
THEME_DIR="${PROJECT_DIR}/wp-content/themes/working-theme"
cd "${PROJECT_DIR}"

# --- Pretty output -----------------------------------------------------------
if [ -t 1 ]; then
  C_RESET="$(printf '\033[0m')"; C_BOLD="$(printf '\033[1m')"
  C_BLUE="$(printf '\033[34m')"; C_GREEN="$(printf '\033[32m')"
  C_YELLOW="$(printf '\033[33m')"; C_RED="$(printf '\033[31m')"
else
  C_RESET=""; C_BOLD=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi

info()    { printf '%s\n' "${C_BLUE}==>${C_RESET} $*"; }
step()    { printf '%s\n' "${C_BOLD}${C_BLUE}::${C_RESET} ${C_BOLD}$*${C_RESET}"; }
success() { printf '%s\n' "${C_GREEN}✓${C_RESET} $*"; }
warn()    { printf '%s\n' "${C_YELLOW}!${C_RESET} $*" >&2; }
fail()    { printf '%s\n' "${C_RED}✗ $*${C_RESET}" >&2; exit 1; }

# --- Prerequisites -----------------------------------------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' not found. $2"
}

require_docker() {
  require_cmd docker "Install Docker: https://docs.docker.com/get-docker/"
  docker compose version >/dev/null 2>&1 || \
    fail "Docker Compose v2 not available. Update Docker Desktop / install the compose plugin."
  docker info >/dev/null 2>&1 || fail "Docker daemon is not running. Start Docker and retry."
}

# --- Secrets -----------------------------------------------------------------
# 64 hex chars: safe in .env (no $, quotes, or spaces to break interpolation).
gen_secret() { openssl rand -hex 32; }
# A human-typable strong password.
gen_password() { openssl rand -base64 24 | tr -d '/+=' | cut -c1-24; }

# --- .env helpers ------------------------------------------------------------
ENV_FILE="${PROJECT_DIR}/.env"

# Read a key from .env (value as-is, first match).
env_get() {
  local key="$1"
  [ -f "${ENV_FILE}" ] || return 0
  sed -n "s/^${key}=\(.*\)$/\1/p" "${ENV_FILE}" | head -n1
}

# Set/replace a key in .env (creates the line if missing). Value passed literally.
env_set() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
    # Use a temp file; avoid sed delimiter clashes by using awk.
    awk -v k="${key}" -v v="${value}" \
      'BEGIN{FS=OFS="="} $1==k{print k"="v; next} {print}' \
      "${ENV_FILE}" > "${ENV_FILE}.tmp" && mv "${ENV_FILE}.tmp" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}

# --- Docker wrappers ---------------------------------------------------------
dc()  { docker compose "$@"; }

# WP-CLI: run as root with --allow-root so it can read wp-config (www-data owned)
# and write to the bind-mounted wp-content regardless of host UID.
wp() { docker compose run --rm -T -u root wpcli wp --allow-root "$@"; }

# Composer for the theme, pinned to PHP 8.3 to match the runtime container.
composer_theme() {
  docker run --rm \
    -v "${THEME_DIR}":/app -w /app \
    composer:2 "$@"
}

# Node/Vite one-off command in the theme.
node_run() { docker compose run --rm -T node "$@"; }

# --- Ports -------------------------------------------------------------------
# True if something is already listening on the given TCP port (host side).
# Uses bash /dev/tcp so no extra tools are required on the server.
port_in_use() {
  local p="$1"
  (exec 3<>"/dev/tcp/127.0.0.1/${p}") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
  return 1
}

# Ports already handed out during this run (not yet listening, but reserved).
ASSIGNED_PORTS=""

# A port is taken if it's already listening OR already reserved this run.
port_taken() {
  local p="$1"
  case " ${ASSIGNED_PORTS} " in *" ${p} "*) return 0 ;; esac
  port_in_use "${p}"
}

# Find the first free port at/after $1 and set FOUND_PORT (no subshell, so the
# reservation persists). Reserves it so the next call won't pick the same one.
find_free_port() {
  local p="$1"
  while port_taken "${p}"; do p=$((p + 1)); done
  ASSIGNED_PORTS="${ASSIGNED_PORTS} ${p}"
  FOUND_PORT="${p}"
}

# Is the project's Docker stack already running?
stack_running() { [ -n "$(dc ps -q wordpress 2>/dev/null)" ]; }

# --- Misc --------------------------------------------------------------------
# Wait until an HTTP URL returns any response (max ~120s).
wait_for_http() {
  local url="$1" tries=60
  info "Waiting for ${url} ..."
  while [ "${tries}" -gt 0 ]; do
    if curl -fsS -o /dev/null -m 3 "${url}" 2>/dev/null; then
      success "Reachable: ${url}"; return 0
    fi
    # Treat any HTTP status (incl. 302/403) as "up".
    if curl -sS -o /dev/null -m 3 "${url}" 2>/dev/null; then
      success "Reachable: ${url}"; return 0
    fi
    sleep 2; tries=$((tries - 1))
  done
  fail "Timed out waiting for ${url}"
}
