# CLAUDE.md

Project context for Claude Code when working in this repository.

## What this repo is

A **template/boilerplate** for a WordPress development stack — Nginx + PHP 8.3-FPM + MariaDB,
orchestrated with Docker Compose. It is not itself a live WordPress site: cloning it (or
downloading a release ZIP) and running `./setup.sh` turns it into a fresh project. Beyond local
dev, it also covers going to production self-hosted via a Cloudflare Zero Trust Tunnel and
backing up the db + files — see "Two distinct production paths" and "Backup system" below.

## Architecture

Three services in `docker-compose.yml`, no explicit network (default Compose network):

| Service | Image                  | Role                                            |
|---------|------------------------|--------------------------------------------------|
| `nginx` | `nginx:latest`         | Web server, bound to `127.0.0.1:${NGINX_PORT}`, proxies PHP to `php:9000` |
| `php`   | built from `php/Dockerfile` (`php:8.3-fpm` + WP-CLI + gd/imagick/intl/etc.) | Runs as host `${UID}:${GID}` so bind-mounted files keep host ownership |
| `db`    | `mariadb:lts`          | Data in the named volume `db_data` (survives restarts, wiped only by `make nuke`) |

`docker-compose.prod.yml` adds two more services on top of the above: `cloudflared` (see
production path 2 below) and an optional `backup` service (profile `backup`, only started when
`BACKUP_SCHEDULER=container`) built from `backup/Dockerfile` — see "Backup system" below.

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
├── backup/
│   ├── Dockerfile                # alpine + mariadb-client + rsync, runs scripts/backup.sh on a cron loop
│   └── entrypoint.sh
├── scripts/
│   ├── backup.sh                  # dump db + tar public_html/, apply retention, optional remote sync
│   └── backup-restore.sh          # restore db + files from a backup set (destructive)
├── public_html/                 # WordPress webroot — gitignored, created by setup.sh
├── logs/                        # nginx logs — gitignored, created by setup.sh
├── backups/                      # default BACKUP_PATH — gitignored, created on first backup
├── .github/workflows/release.yml  # this template repo's own CI (zips + tags releases)
├── src/
│   ├── deploy.yml                # FTP-deploy workflow template for the *separate* production repo
│   └── gitignore                 # gitignore template for that separate production repo
└── .claude/skills/
    ├── make-commands/            # how to use the Makefile
    ├── production-release/       # how to go live via Cloudflare Tunnel
    └── backup/                   # how to back up/restore/schedule db + files
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
| `BACKUP_PATH` | Where backups are written (default `./backups`) |
| `BACKUP_RETENTION_DAYS` | Days to keep old backups before pruning |
| `BACKUP_SCHEDULER` | `host` (cron entry on the host runs `scripts/backup.sh`) or `container` (starts the `backup` service from `docker-compose.prod.yml`) |
| `BACKUP_SCHEDULE_CRON` | Cron expression used only when `BACKUP_SCHEDULER=container` |
| `BACKUP_EXCLUDE_PATHS` | Space-separated paths under `public_html/` to exclude from the files archive |
| `BACKUP_REMOTE_PATH` / `BACKUP_REMOTE_SYNC_CMD` | Optional remote sync destination + command run after each backup (default `rsync -az`, swappable for `rclone sync`) |

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
   **production-release** skill. Since Cloudflare terminates TLS at its edge, going live also
   requires hardening `public_html/wp-config.php` to trust the forwarded scheme (see README
   "Required `wp-config.php` hardening" and `setup.sh` — same content lives in both, kept in
   sync manually).

## Backup system

`make backup` / `make backup-db` / `make backup-files` run `scripts/backup.sh` to dump the DB
and/or tar `public_html/` into `BACKUP_PATH`, prune anything older than
`BACKUP_RETENTION_DAYS`, and optionally sync to `BACKUP_REMOTE_PATH` via
`BACKUP_REMOTE_SYNC_CMD`. `make backup-restore FILE_DB=... FILE_FILES=...` runs
`scripts/backup-restore.sh` and is destructive. `make backup-list` lists what's in `BACKUP_PATH`.

Scheduling is controlled by `BACKUP_SCHEDULER`:
- `host` — add a cron entry on the host that runs `scripts/backup.sh` (or `make backup`) directly.
- `container` — starts the `backup` service defined in `docker-compose.prod.yml` (profile
  `backup`, only via `make prod-up`), which loops `scripts/backup.sh` on `BACKUP_SCHEDULE_CRON`
  inside a container built from `backup/Dockerfile`.

Full setup and examples: the **backup** skill.

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
