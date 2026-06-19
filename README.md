# OBS WordPress

Dockerized WordPress with a Blade-based custom theme (Sage 11 + Vite + Tailwind),
fully provisioned by a single setup script. Identical on local machines and the VPS.

## Requirements

Only **Docker** (with Compose v2). Everything else — PHP, MySQL, WP-CLI, Composer,
Node — runs inside containers. (`openssl` and `curl` are used by the scripts and ship
with macOS/Linux.)

## Starting a new project from this starter kit

This repo is a **starter kit**. When you begin a real project from it, push your work
to a **new, separate repo** — not back into the starter. Two ways to do that:

### Option A — Fresh start (recommended)

Drops the starter's git history so the new project begins clean.

```bash
# 1. Get the starter code (no history needed)
git clone https://github.com/<you>/obs-wp-starter.git my-project
cd my-project
rm -rf .git

# 2. Start a fresh repo
git init
git add -A
git commit -m "Initial commit from OBS WordPress starter kit"

# 3. Create the NEW empty repo and push to it
#    With the GitHub CLI (creates the repo for you):
gh repo create <you>/my-project --private --source=. --remote=origin --push
#    …or manually, if you already created an empty repo on GitHub:
git branch -M main
git remote add origin https://github.com/<you>/my-project.git
git push -u origin main
```

### Option B — Keep history & stay linked to the starter

Use this if you want to pull future starter-kit improvements into the project.

```bash
git clone https://github.com/<you>/obs-wp-starter.git my-project
cd my-project

# Re-point: the starter becomes "upstream", your project repo becomes "origin"
git remote rename origin upstream
git remote add origin https://github.com/<you>/my-project.git
git push -u origin main

# Later, pull improvements made to the starter kit:
git pull upstream main
```

> ⚠️ Always check `git remote -v` after cloning a starter — make sure `origin`
> points to **your project repo**, so you never accidentally push project work into
> the starter kit.

Then provision it:

```bash
bash bin/setup.sh
```

## Quick start (existing project)

For a project that's already on its own repo, just clone and run setup:

```bash
git clone <YOUR_REPO_URL> obs-wp
cd obs-wp
bash bin/setup.sh
```

That's it. The script:

1. Generates `.env` (random DB + admin passwords, WP salts) if missing.
2. Picks free host ports automatically if the defaults are taken.
3. Starts the Docker stack.
4. Installs theme dependencies (Composer/Acorn) and builds assets (Vite/Tailwind).
5. Installs WordPress + activates the theme + installs plugins (ACF, WP Mail SMTP,
   Query Monitor).
6. Prints the **site URL, wp-admin login, DB credentials, and dev/deploy commands**.

Re-running `setup.sh` is safe — it skips anything already done.

## Daily development (live reload)

```bash
bash bin/dev.sh
```

Starts the Vite dev server with hot-module-reload. Edit any `.blade.php`, CSS, or JS
in `wp-content/themes/working-theme/` and the browser updates instantly — no manual
rebuild. Press `Ctrl-C` to stop the watcher (containers keep running).

Open the site at the URL printed by setup (default `http://localhost:8080`).

## Building theme assets (npm)

Node runs **inside the `node` container** — you don't need Node installed on your
machine. The container's working directory is already the theme, so no `cd` needed.

```bash
# Live dev server with hot reload (same as bin/dev.sh):
docker compose exec node npm run dev

# Production build:
docker compose run --rm node npm run build

# Any other npm command:
docker compose exec node npm <command>       # stack already up
docker compose run --rm node npm <command>   # one-off (e.g. right after a clone)

# examples:
docker compose exec node npm install <package>   # add a dependency
docker compose exec node npm ci                  # clean install from lockfile
```

- `exec` runs in the already-running `node` container — use it for `dev` and quick
  commands.
- `run --rm` spins up a throwaway container — use it when the stack isn't up.
- After any `npm run build`, asset filenames get new hashes and WordPress picks them
  up automatically (no cache flush needed). While the dev server is running, the site
  loads assets live from it instead of the built files.

Prefer running natively? Install Node 20+, then from
`wp-content/themes/working-theme/` run `npm install` and `npm run dev` / `npm run
build`. The Docker route is recommended so every machine uses the same Node version.

## Deploying (on the VPS)

```bash
git pull && bash bin/deploy.sh
# or let the script pull for you:
bash bin/deploy.sh --pull
```

The deploy script installs production dependencies, builds optimized/cache-busted
assets, runs DB migrations, clears caches (Blade views, Acorn, object cache,
rewrites), fixes permissions, and runs a health check.

## How it's wired

- **WordPress core** is provided by the `wordpress:php8.3-apache` image and lives in a
  Docker volume — it is **not** in git.
- Only **`wp-content`** is bind-mounted from the host, so git tracks just our code.
- The **database** lives in a Docker volume and is never committed. Use phpMyAdmin
  (URL printed by setup) or export a SQL dump to share data.
- **Secrets** live in `.env` (git-ignored). `.env.example` is the committed template.

### What git tracks vs. ignores

Tracked: `docker-compose.yml`, `bin/*.sh`, `.env.example`, `.gitignore`, the
`working-theme` source, custom plugins, docs.

Ignored: `.env`, WP core, `wp-content/uploads/`, third-party plugins,
`node_modules/`, `vendor/`, built assets (`public/build/` — rebuilt on deploy), DB.

To track a custom plugin, add an exception in `.gitignore`, e.g.
`!/wp-content/plugins/my-plugin/`.

## Project layout

```
.
├── docker-compose.yml        # wordpress, db, wpcli, node (Vite), phpmyadmin
├── .env.example              # config template (copied to .env by setup)
├── bin/
│   ├── lib.sh                # shared shell helpers
│   ├── setup.sh              # one-shot provisioning (any machine)
│   ├── dev.sh                # local dev + Vite HMR
│   └── deploy.sh             # production deploy
└── wp-content/
    ├── themes/working-theme/ # Sage 11 (Blade + Vite + Tailwind)
    ├── plugins/              # custom plugins tracked; others ignored
    └── mu-plugins/
```

## Services & default ports

| Service     | URL / port (default)        | Notes                                  |
|-------------|-----------------------------|----------------------------------------|
| WordPress   | http://localhost:8080       | `WP_HTTP_PORT`                         |
| phpMyAdmin  | http://localhost:8081       | `PMA_HTTP_PORT`                        |
| Vite (HMR)  | http://localhost:5173       | `VITE_PORT`                            |

If a default port is busy, `setup.sh` automatically picks the next free one and
records it in `.env`.

## Common commands

```bash
docker compose ps                 # service status
docker compose logs -f wordpress  # tail logs
docker compose down               # stop (data persists in volumes)
docker compose down -v            # stop AND delete the database volume

# Run any WP-CLI command:
docker compose run --rm -u root wpcli wp --allow-root <command>
```

## Setting up on a server (VPS)

First time on the server:

```bash
# 1. Install Docker (once) — https://docs.docker.com/engine/install/
# 2. Clone the repo
git clone <YOUR_REPO_URL> obs-wp
cd obs-wp

# 3. (Recommended) edit production settings before first run
#    Create .env from the template and set your domain + env:
cp .env.example .env
#    then edit .env:  WP_HOME=https://your-domain.com   WP_ENV=production
#    (leave the password/salt fields blank — setup.sh fills them)

# 4. Provision everything
bash bin/setup.sh
```

`setup.sh` prints the admin login and DB credentials at the end — save them.

### Subsequent deploys

```bash
git pull && bash bin/deploy.sh
# or let the script pull for you:
bash bin/deploy.sh --pull
```

### Production notes

- Set `WP_HOME` to your real domain and `WP_ENV=production` in `.env` before the
  first `setup.sh` (or update and re-run `deploy.sh`).
- Put a reverse proxy (Nginx / Caddy / Traefik) with TLS in front of the WordPress
  container's published port (`WP_HTTP_PORT`).
- Restrict or firewall the phpMyAdmin port (`PMA_HTTP_PORT`) in production.
- Back up the database volume regularly:
  ```bash
  docker compose exec -T db mysqldump -u root -p"$DB_ROOT_PASSWORD" "$DB_NAME" > backup.sql
  ```

## Moving the site / sharing data between machines

Code (theme, plugins, config) travels through git. The **database does not** — it
lives in a Docker volume. To copy content from one machine to another, export and
import a SQL dump:

```bash
# On the source machine
docker compose run --rm -T -u root wpcli wp --allow-root db export - > db.sql

# On the target machine (after setup.sh)
docker compose run --rm -T -u root wpcli wp --allow-root db import - < db.sql
# Fix URLs if the domain differs:
docker compose run --rm -T -u root wpcli wp --allow-root \
  search-replace 'https://old-domain' 'https://new-domain'
```

Uploaded media lives in `wp-content/uploads/` (git-ignored) — copy it across with
`rsync`/`scp` if needed.
