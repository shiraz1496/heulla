#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Deploy on the server. Run after pulling the latest code:
#
#   git pull && bash bin/deploy.sh
#
# Ensures the stack is up, installs production deps, builds optimized assets,
# clears caches, runs DB migrations, fixes permissions, and health-checks.
# Pass --pull to have the script run 'git pull' for you.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_docker
[ -f "${ENV_FILE}" ] || fail "No .env found. Run 'bash bin/setup.sh' first on this machine."

if [ "${1:-}" = "--pull" ]; then
  step "Pulling latest code"
  require_cmd git "Needed for --pull."
  git -C "${PROJECT_DIR}" pull --ff-only
fi

WP_HTTP_PORT="$(env_get WP_HTTP_PORT)"; WP_HTTP_PORT="${WP_HTTP_PORT:-8080}"
LOCAL_URL="http://localhost:${WP_HTTP_PORT}"

step "Pulling images & starting services"
dc pull --quiet || warn "Image pull skipped/failed (continuing)"
dc up -d
wait_for_http "${LOCAL_URL}"

step "Installing production dependencies (Composer)"
composer_theme install --no-interaction --prefer-dist --no-progress \
  --no-dev --optimize-autoloader
success "Composer (no-dev) installed"

step "Building optimized, cache-busted assets"
if [ -f "${THEME_DIR}/package-lock.json" ]; then
  node_run npm ci --no-audit --no-fund
else
  node_run npm install --no-audit --no-fund
fi
node_run npm run build
success "Assets built"

step "Running database migrations"
wp core update-db >/dev/null && success "Database up to date"

step "Clearing caches"
# Acorn / Blade view + app caches (no-op-safe if commands are unavailable).
wp acorn view:clear   >/dev/null 2>&1 || true
wp acorn cache:clear  >/dev/null 2>&1 || true
wp acorn optimize:clear >/dev/null 2>&1 || true
wp cache flush         >/dev/null 2>&1 || true
wp rewrite flush --hard >/dev/null 2>&1 || true
success "Caches cleared & rewrites flushed"

step "Fixing file permissions"
dc exec -T -u root wordpress sh -c \
  'mkdir -p wp-content/uploads && chown -R www-data:www-data wp-content/uploads' || \
  warn "Could not chown uploads (non-fatal)"

step "Health check"
code="$(curl -s -o /dev/null -w '%{http_code}' -m 10 "${LOCAL_URL}" || echo 000)"
case "${code}" in
  2*|3*) success "Site responded HTTP ${code}";;
  *)     fail "Health check failed (HTTP ${code}). Check 'docker compose logs wordpress'.";;
esac

cat <<EOF

${C_GREEN}${C_BOLD}✓ Deploy complete${C_RESET}
  Site:  ${LOCAL_URL}
  Admin: ${LOCAL_URL}/wp-admin
EOF
