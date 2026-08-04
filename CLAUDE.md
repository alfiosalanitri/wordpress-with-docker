# CLAUDE.md

Project context for Claude Code when working in this repository.

## What this repo is

A **template/boilerplate** for a local WordPress development stack — Nginx + PHP 8.3-FPM +
MariaDB, orchestrated with Docker Compose. It is not itself a live WordPress site: cloning it
(or downloading a release ZIP) and running `./setup.sh` turns it into a fresh project.

## Architecture

Three services in `docker-compose.yml`, no explicit network (default Compose network):

| Service | Image                  | Role                                            |
|---------|------------------------|--------------------------------------------------|
| `nginx` | `nginx:latest`         | Web server, bound to `127.0.0.1:${NGINX_PORT}`, proxies PHP to `php:9000` |
| `php`   | built from `php/Dockerfile` (`php:8.3-fpm` + WP-CLI + gd/imagick/intl/etc.) | Runs as host `${UID}:${GID}` so bind-mounted files keep host ownership |
| `db`    | `mariadb:lts`          | Data in the named volume `db_data` (survives restarts, wiped only by `make nuke`) |

Bind mounts: `./public_html` → `/var/www/html` (nginx + php), `./logs` → nginx logs,
`./nginx/www.conf` → nginx vhost config, `./php/php.ini` → PHP overrides.

## Directory structure

```
├── docker-compose.yml           # dev stack (nginx, php, db)
├── docker-compose.prod.yml      # production override: adds cloudflared, swaps nginx config
├── .env.example                 # env var template (copied to .env by setup.sh)
├── Makefile                     # all dev + production commands (see make-commands skill)
├── setup.sh                     # interactive bootstrap; ALSO regenerates README.md at the end
├── nginx/
│   ├── www.conf                 # dev vhost (plain HTTP, basic WP hardening)
│   └── production.conf          # production vhost (adds headers, gzip, rate limiting, real_ip)
├── php/
│   ├── Dockerfile
│   └── php.ini
├── public_html/                 # WordPress webroot — gitignored, created by setup.sh
├── logs/                        # nginx logs — gitignored, created by setup.sh
├── .github/workflows/release.yml  # this template repo's own CI (zips + tags releases)
├── src/
│   ├── deploy.yml                # FTP-deploy workflow template for the *separate* production repo
│   └── gitignore                 # gitignore template for that separate production repo
└── .claude/skills/
    ├── make-commands/            # how to use the Makefile
    └── production-release/       # how to go live via Cloudflare Tunnel
```

## Environment variables (`.env`, generated from `.env.example`)

| Variable | Purpose |
|---|---|
| `PROJECT_NAME` | Compose project name |
| `NGINX_PORT` | Local port nginx is bound to (`127.0.0.1` only) |
| `MYSQL_ROOT_PASSWORD` / `MYSQL_DATABASE` / `MYSQL_USER` / `MYSQL_PASSWORD` | MariaDB credentials |
| `UID` / `GID` | Host user, auto-filled by `setup.sh`, used so `php` runs as the host user |
| `CLOUDFLARE_TUNNEL_TOKEN` | Production only — token for the `cloudflared` tunnel (see below) |
| `PRODUCTION_DOMAIN` | Production only — the public hostname routed through the tunnel |

## Local dev workflow

1. `./setup.sh` — interactive: writes `.env`, downloads WordPress into `public_html/`, wires up
   `.gitignore` and the FTP `deploy.yml` template, optionally builds and starts the stack.
2. Day to day: `make up` / `make down` / `make logs` / `make shell-php` / `make wp-cli CMD="..."`.
3. Full command reference: use the **make-commands** skill, or `make help`.

## Two distinct "production" paths — don't conflate them

This repo documents **two unrelated** ways to go to production:

1. **FTP theme deploy** (pre-existing): `setup.sh` generates `.github/workflows/deploy.yml` from
   `src/deploy.yml`, meant for a **separate, leaner repo** (just the theme + a DB dump) pushed to
   classic shared hosting over FTP on every push to `main`. See README's
   "Production Repo Workflow" section.
2. **Self-hosted release via Cloudflare Zero Trust Tunnel** (new): runs the *same* Docker stack
   from *this* repo in production, with a `cloudflared` container tunneling public traffic
   straight to `nginx` — no open ports, no local TLS certs (Cloudflare terminates TLS at the
   edge). Driven by `docker-compose.prod.yml` + `make prod-up`/`prod-down`/`prod-logs`/`prod-ps`.
   See README's "Self-Hosted Production Release (Cloudflare Tunnel)" section and the
   **production-release** skill.

## Gotchas

- **`setup.sh` overwrites `README.md`** near the end of its run (heredoc, generates a leaner
  project-specific README). Any documentation added only to the root `README.md` in *this*
  template repo will be lost the first time a downstream project runs `setup.sh` — the heredoc
  inside `setup.sh` must be kept in sync with README changes that should survive setup.
- `public_html/`, `logs/`, and `.env` are gitignored and don't exist until `setup.sh` runs.
- Permissions on `public_html/` are tied to the host `UID`/`GID` baked into `.env`; see the
  README's "Permissions" section or `make wp-permissions` if they drift.
- `make nuke` and `make clean` are destructive (drop the DB volume / remove logs) — confirm
  before running them on anything that matters.
