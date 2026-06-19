#!/usr/bin/env bash
# =============================================================================
# setup.sh — Provision this WordPress project on any machine (local or VPS).
#
#   Run from anywhere:  bash bin/setup.sh
#
# Idempotent: safe to re-run. Brings up Docker, installs theme deps, builds
# assets, installs WordPress + plugins, and prints login details at the end.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step "Checking prerequisites"
require_docker
require_cmd openssl "Needed to generate secrets."
require_cmd curl "Needed for readiness checks."
success "Docker, openssl, curl present"

# -----------------------------------------------------------------------------
step "Preparing .env"
if [ ! -f "${ENV_FILE}" ]; then
  cp "${PROJECT_DIR}/.env.example" "${ENV_FILE}"
  success "Created .env from .env.example"
else
  info ".env already exists — filling only blank secrets"
fi

# Fill any blank secrets without touching values the user has set.
[ -z "$(env_get DB_PASSWORD)" ]      && env_set DB_PASSWORD "$(gen_password)"
[ -z "$(env_get DB_ROOT_PASSWORD)" ] && env_set DB_ROOT_PASSWORD "$(gen_password)"
[ -z "$(env_get WP_ADMIN_PASSWORD)" ] && env_set WP_ADMIN_PASSWORD "$(gen_password)"

for salt in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY \
            AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
  [ -z "$(env_get "${salt}")" ] && env_set "${salt}" "$(gen_secret)"
done
success "Secrets ready"

# Load values we need for install + summary.
WP_HOME="$(env_get WP_HOME)";           WP_HOME="${WP_HOME:-http://localhost:8080}"
WP_HTTP_PORT="$(env_get WP_HTTP_PORT)"; WP_HTTP_PORT="${WP_HTTP_PORT:-8080}"
PMA_HTTP_PORT="$(env_get PMA_HTTP_PORT)"; PMA_HTTP_PORT="${PMA_HTTP_PORT:-8081}"
VITE_PORT="$(env_get VITE_PORT)";       VITE_PORT="${VITE_PORT:-5173}"
WP_TITLE="$(env_get WP_TITLE)";         WP_TITLE="${WP_TITLE:-WordPress}"
WP_ADMIN_USER="$(env_get WP_ADMIN_USER)"; WP_ADMIN_USER="${WP_ADMIN_USER:-admin}"
WP_ADMIN_PASSWORD="$(env_get WP_ADMIN_PASSWORD)"
WP_ADMIN_EMAIL="$(env_get WP_ADMIN_EMAIL)"; WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:-admin@example.com}"
DB_NAME="$(env_get DB_NAME)"; DB_USER="$(env_get DB_USER)"; DB_PASSWORD="$(env_get DB_PASSWORD)"

# Auto-pick free host ports (only when the stack isn't already running, so we
# never reassign ports our own containers are legitimately holding).
if ! stack_running; then
  for pair in "WP_HTTP_PORT:${WP_HTTP_PORT}" "PMA_HTTP_PORT:${PMA_HTTP_PORT}" "VITE_PORT:${VITE_PORT}"; do
    key="${pair%%:*}"; want="${pair#*:}"
    find_free_port "${want}"; free="${FOUND_PORT}"
    if [ "${free}" != "${want}" ]; then
      warn "Port ${want} is busy — using ${free} for ${key}"
      env_set "${key}" "${free}"
      eval "${key}=${free}"
    fi
  done
  # Keep WP_HOME's port in sync if it pointed at the (now changed) default.
  if printf '%s' "${WP_HOME}" | grep -qE 'localhost:[0-9]+'; then
    WP_HOME="http://localhost:${WP_HTTP_PORT}"
    env_set WP_HOME "${WP_HOME}"
  fi
fi

LOCAL_URL="http://localhost:${WP_HTTP_PORT}"

# -----------------------------------------------------------------------------
step "Starting Docker services (db, wordpress, node, phpmyadmin)"
dc up -d
wait_for_http "${LOCAL_URL}"

# -----------------------------------------------------------------------------
step "Installing theme dependencies (Composer / Acorn)"
composer_theme install --no-interaction --prefer-dist --no-progress
success "Composer dependencies installed"

step "Installing & building theme assets (Vite + Tailwind)"
node_run npm install --no-audit --no-fund
node_run npm run build
success "Production assets built"

# -----------------------------------------------------------------------------
step "Installing WordPress"
if wp core is-installed >/dev/null 2>&1; then
  info "WordPress already installed — skipping core install"
else
  wp core install \
    --url="${WP_HOME}" \
    --title="${WP_TITLE}" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASSWORD}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --skip-email
  success "WordPress installed"
fi

step "Configuring WordPress"
wp rewrite structure '/%postname%/' --hard >/dev/null
wp theme activate working-theme >/dev/null && success "Theme 'working-theme' activated"

step "Installing plugins (ACF, WP Mail SMTP, Query Monitor)"
wp plugin install advanced-custom-fields wp-mail-smtp query-monitor --activate >/dev/null
success "Plugins installed & activated"

step "Fixing uploads permissions"
dc exec -T -u root wordpress sh -c \
  'mkdir -p wp-content/uploads && chown -R www-data:www-data wp-content/uploads' || \
  warn "Could not chown uploads (non-fatal on macOS)"

# -----------------------------------------------------------------------------
cat <<EOF

${C_GREEN}${C_BOLD}============================================================${C_RESET}
${C_GREEN}${C_BOLD}  ✓ Setup complete — WordPress is up and running${C_RESET}
${C_GREEN}${C_BOLD}============================================================${C_RESET}

${C_BOLD}Site${C_RESET}
  Front-end:   ${LOCAL_URL}
  Admin:       ${LOCAL_URL}/wp-admin

${C_BOLD}Admin login${C_RESET}
  Username:    ${WP_ADMIN_USER}
  Password:    ${WP_ADMIN_PASSWORD}
  Email:       ${WP_ADMIN_EMAIL}

${C_BOLD}Database${C_RESET}
  Name:        ${DB_NAME}
  User:        ${DB_USER}
  Password:    ${DB_PASSWORD}
  Host:        db:3306  (from containers)
  phpMyAdmin:  http://localhost:${PMA_HTTP_PORT}

${C_BOLD}Develop (live reload / HMR)${C_RESET}
  bash bin/dev.sh           # starts Vite on http://localhost:${VITE_PORT}
  Edit Blade/CSS/JS in wp-content/themes/working-theme → browser updates live

${C_BOLD}Deploy (on the server, after 'git pull')${C_RESET}
  bash bin/deploy.sh

${C_YELLOW}Secrets above live in .env (git-ignored). Keep them safe.${C_RESET}
EOF
