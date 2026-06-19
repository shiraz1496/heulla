#!/usr/bin/env bash
# =============================================================================
# dev.sh — Start local development with Vite hot-module-reload (HMR).
#
#   bash bin/dev.sh
#
# Brings the stack up (if needed) and runs the Vite dev server inside the node
# container. Save a .blade.php / .css / .js file and the browser updates live —
# no manual rebuild. Press Ctrl-C to stop the watcher (containers stay up).
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_docker
[ -f "${ENV_FILE}" ] || fail "No .env found. Run 'bash bin/setup.sh' first."

VITE_PORT="$(env_get VITE_PORT)"; VITE_PORT="${VITE_PORT:-5173}"
WP_HTTP_PORT="$(env_get WP_HTTP_PORT)"; WP_HTTP_PORT="${WP_HTTP_PORT:-8080}"

step "Ensuring containers are running"
dc up -d
success "Containers up"

if [ ! -d "${THEME_DIR}/node_modules" ]; then
  step "Installing node modules (first run)"
  node_run npm install --no-audit --no-fund
fi

step "Starting Vite dev server (HMR) on http://localhost:${VITE_PORT}"
info "Open the site at  http://localhost:${WP_HTTP_PORT}"
info "Press Ctrl-C to stop the watcher."
dc exec node npm run dev
