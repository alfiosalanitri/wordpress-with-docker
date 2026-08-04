---
name: make-commands
description: How to use this project's Makefile — starting/stopping the Docker stack, encrypting/decrypting .env, following logs, opening shells, running WP-CLI, backing up/restoring the database, cleanup, and the production release targets. Use whenever asked to start or stop the stack, run a WordPress/WP-CLI command, back up or restore the database, tail logs, open a shell in a container, or release to production.
---

# Makefile commands

All targets read `.env` automatically (`-include .env` + `export` at the top of the `Makefile`),
so `PROJECT_NAME`, `NGINX_PORT`, `MYSQL_*`, `UID`/`GID`, `CLOUDFLARE_TUNNEL_TOKEN`, and
`PRODUCTION_DOMAIN` are all available inside recipes without re-exporting them. Run `make help`
for the live list; this file explains what each group does and when to reach for it.

## Containers (local dev)

| Command | What it does |
|---|---|
| `make up` | `docker compose up -d`, then prints the local URL |
| `make down` | Stops and removes containers (keeps the `db_data` volume) |
| `make restart` | Restarts all containers, prints the local URL |
| `make ps` / `make status` | Container status |

## Env encryption

| Command | What it does |
|---|---|
| `make env-encrypt` | AES-256-CBC encrypts `.env` → `.env.encrypted` (prompts for a passphrase twice) so it can be safely committed |
| `make env-decrypt` | Decrypts `.env.encrypted` → `.env` (refuses to run if `.env` already exists — remove/rename it first) |

## Logs

`make logs` (all services), `make logs-nginx`, `make logs-php`, `make logs-db` — all `docker
compose logs -f`, so they block until you Ctrl-C.

## Shells

`make shell-php` (bash), `make shell-db` (opens the `mariadb` client, pre-authenticated with
`MYSQL_USER`/`MYSQL_PASSWORD`/`MYSQL_DATABASE`), `make shell-nginx` (sh, since the nginx image
has no bash).

## WordPress

- `make wp-permissions` — resets `public_html/` ownership to `www-data` and applies
  `gu+rws`. Requires `sudo`. Use after manual file operations (e.g. editing as root) leave the
  wrong owner behind.
- `make wp-cli CMD="..."` — runs any WP-CLI command inside the `php` container, e.g.
  `make wp-cli CMD="plugin list"` or `make wp-cli CMD="option update siteurl https://example.com"`.
  Always runs with `--allow-root`.

## Database

- `make db-backup` — dumps the DB to `./<MYSQL_DATABASE>.sql` at the repo root. This is the file
  meant to be committed into the *separate* FTP production repo (see the README's "Production
  Repo Workflow" section) — it is unrelated to the Cloudflare Tunnel production path.
- `make db-restore FILE=path/to/dump.sql` — restores a dump. **Destructive**: overwrites the
  current database contents with no confirmation prompt. Double-check `FILE=` before running.

## Cleanup

- `make clean` — stops containers and deletes `logs/*.log`. Non-destructive to data.
- `make nuke` — **destructive**: removes containers, the `db_data` volume (all WordPress data
  gone), the locally built PHP image, and logs. Requires typing `yes` at a confirmation prompt.
  Never run this against anything you haven't already backed up with `make db-backup`.

## Production release (Cloudflare Tunnel)

| Command | What it does |
|---|---|
| `make prod-up` | Brings up `docker-compose.yml` + `docker-compose.prod.yml` (adds `cloudflared`, swaps nginx to `nginx/production.conf`). Refuses to run if `CLOUDFLARE_TUNNEL_TOKEN` isn't set in `.env`. |
| `make prod-down` | Stops the production stack |
| `make prod-restart` | Restarts the production stack |
| `make prod-logs` | Follows logs of the production stack, including `cloudflared` |
| `make prod-ps` | Production stack container status |

These targets always pass both compose files (`-f docker-compose.yml -f
docker-compose.prod.yml`) — never run plain `docker compose` commands against
`docker-compose.prod.yml` alone, it only contains the override/diff. For the full one-time
Cloudflare dashboard setup (creating the tunnel, adding the public hostname), use the
**production-release** skill.

## Typical workflows

- **First time up**: `./setup.sh` → `make up` → open the printed URL → run the WordPress
  install wizard (DB host is `db`).
- **Daily dev loop**: `make logs-php` in one terminal, `make shell-php` or `make wp-cli
  CMD="..."` in another.
- **Before deploying the FTP production repo**: `make db-backup`, then commit the resulting
  `.sql` file into that separate repo.
- **Going to production on this repo**: see the **production-release** skill, then `make
  prod-up`.
