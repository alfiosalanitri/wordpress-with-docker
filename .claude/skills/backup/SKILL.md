---
name: backup
description: How to back up and restore the database + public_html/ files for this WordPress+Docker stack, and how to schedule it (host cron or a dedicated container in production). Use when asked to set up backups, schedule backups, restore a backup, configure backup retention or remote sync. Distinct from `make db-backup`/`make db-restore`, which stay dedicated to the separate FTP production repo workflow — don't mix the two up.
---

# Backup & restore (db + files)

`scripts/backup.sh` and `scripts/backup-restore.sh` back up and restore both the MariaDB database
and `public_html/` together, with timestamped filenames, configurable retention, and an optional
remote sync. This is unrelated to `make db-backup`/`make db-restore`, which dump an *uncompressed,
unretained* `.sql` file meant to be committed into the separate FTP theme-deploy repo (see the
README's "Production Repo Workflow" section) — don't conflate the two.

## 1. Manual backups

```bash
make backup          # db_<timestamp>.sql.gz + files_<timestamp>.tar.gz in BACKUP_PATH
make backup-db       # database only
make backup-files    # files only (public_html/)
make backup-list     # list what's currently in BACKUP_PATH
```

These run `./scripts/backup.sh all|db|files` on the host: the DB dump goes through `docker
compose exec -T db mariadb-dump`, the files archive is a `tar czf` of `public_html/`. Both
produce non-zero exit codes on failure (missing container, tar/dump errors, etc.) — safe to
wire into cron or CI and check the exit status.

## 2. Configuration (`.env`)

| Variable | Purpose |
|---|---|
| `BACKUP_PATH` | Destination directory for backup files (default `./backups`) |
| `BACKUP_RETENTION_DAYS` | Backups older than this many days are deleted after each run (default `7`, set `0` to disable) |
| `BACKUP_EXCLUDE_PATHS` | Space-separated paths relative to `public_html/` to exclude from the tar archive, e.g. `wp-content/cache` |
| `BACKUP_REMOTE_PATH` | If set, `scripts/backup.sh` syncs `BACKUP_PATH` here after a successful backup |
| `BACKUP_REMOTE_SYNC_CMD` | The sync tool + flags, invoked as `$BACKUP_REMOTE_SYNC_CMD <BACKUP_PATH> <BACKUP_REMOTE_PATH>`. Default `rsync -az`. Not hardcoded to a provider — set it to `rclone sync` (or anything else that takes `<src> <dest>`) to use a different backend. The script checks the command exists in `PATH` before running and errors clearly if not. |

## 3. Scheduling — `BACKUP_SCHEDULER=host`

Runs backups from a cron entry on the host machine. Neither `setup.sh` nor the Makefile ever
touch the system crontab automatically — add the entry yourself:

```bash
crontab -e
```

```
0 3 * * * cd /path/to/project && ./scripts/backup.sh all >> logs/backup.log 2>&1
```

`scripts/backup.sh` sources `.env` itself when run directly (not just through `make`), so a bare
cron entry like the one above works without going through Make.

## 4. Scheduling — `BACKUP_SCHEDULER=container`

Runs backups from a dedicated `backup` service defined in `docker-compose.prod.yml`, active only
on the production stack (not the local dev `docker-compose.yml`). Set in `.env`:

```
BACKUP_SCHEDULER=container
BACKUP_SCHEDULE_CRON=0 3 * * *
```

Then:

```bash
make prod-up
```

The `backup` service is behind a Compose profile (`profiles: [backup]`); the Makefile only adds
`--profile backup` to the `prod-*` targets when `BACKUP_SCHEDULER=container`, so with
`BACKUP_SCHEDULER=host` the container is never built or started. When active:

- Image: `backup/Dockerfile` — Alpine + `mariadb-client` (for `mariadb-dump`/`mariadb`) + `rsync`
  (default `BACKUP_REMOTE_SYNC_CMD` tool). Swap `rsync` for `rclone` in the Dockerfile if you'd
  rather use that.
- `backup/entrypoint.sh` writes `BACKUP_SCHEDULE_CRON` into `/etc/crontabs/root` and runs
  `crond -f` — Alpine's built-in busybox cron, no extra scheduler daemon.
- Mounts: `public_html/` **read-only**, `scripts/` read-only, `backups/` read-write. Only
  `MYSQL_USER`/`MYSQL_PASSWORD`/`MYSQL_DATABASE` and the `BACKUP_*` vars are passed in — no
  `CLOUDFLARE_TUNNEL_TOKEN`, `MYSQL_ROOT_PASSWORD`, or full `.env` exposure.
- Inside the container, `scripts/backup.sh` detects it's containerized (`/.dockerenv` present)
  and connects to the `db` service directly (`mariadb-dump -h db`) instead of using `docker
  compose exec` — the container has no Docker socket access.
- Check it's running: `make prod-ps` (service `Up`), `make prod-logs` (crond startup + backup
  runs logged to stdout).

## 5. Restore

```bash
make backup-restore FILE_DB=backups/db_20260101_030000.sql.gz FILE_FILES=backups/files_20260101_030000.tar.gz
```

**Destructive**: overwrites the current database and the entire contents of `public_html/`.
`scripts/backup-restore.sh` prints both file paths and requires typing the literal word `yes` to
proceed (same confirmation pattern as `make nuke`) — anything else cancels. It always runs on the
host via `docker compose exec` (never inside the scheduling container). After a restore, run
`make wp-permissions` if file ownership looks wrong.
