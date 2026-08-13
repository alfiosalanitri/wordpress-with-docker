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
| `BACKUP_REMOTE_FETCH_CMD` | Used only by `make backup-restore ... REMOTE=1` to pull a backup down from `BACKUP_REMOTE_PATH` before restoring. Default `rclone copy`. Must stay a **non-destructive copy** (never a sync/mirror command), since it writes into `BACKUP_PATH`. |
| `RCLONE_CONFIG_S3_*` | Credentials/config for an rclone remote named `s3`, used when `BACKUP_REMOTE_PATH` starts with `s3:` — see "Remote storage — S3 and S3-compatible" below. |

## 3. Remote storage — S3 and S3-compatible

`rclone` is installed in the `backup` container image (`backup/Dockerfile`) and is the recommended
tool for `BACKUP_REMOTE_SYNC_CMD`/`BACKUP_REMOTE_FETCH_CMD` when backing up to S3 or an
S3-compatible bucket (Cloudflare R2, Backblaze B2, MinIO, Wasabi, etc.) — no other code changes
are needed, it plugs straight into the existing generic remote-sync hook.

Configure an rclone remote named `s3` via env vars in `.env` (rclone's `RCLONE_CONFIG_<name>_<key>`
convention — no `rclone config` wizard or mounted config file needed):

```
BACKUP_REMOTE_PATH=s3:my-bucket/my-project
BACKUP_REMOTE_SYNC_CMD=rclone sync
BACKUP_REMOTE_FETCH_CMD=rclone copy

# Plain AWS S3
RCLONE_CONFIG_S3_TYPE=s3
RCLONE_CONFIG_S3_PROVIDER=AWS
RCLONE_CONFIG_S3_ACCESS_KEY_ID=<key>
RCLONE_CONFIG_S3_SECRET_ACCESS_KEY=<secret>
RCLONE_CONFIG_S3_REGION=eu-west-1
RCLONE_CONFIG_S3_ENDPOINT=
```

For an S3-compatible endpoint (e.g. Cloudflare R2), set the provider and endpoint instead of a
region:

```
RCLONE_CONFIG_S3_PROVIDER=Cloudflare
RCLONE_CONFIG_S3_ENDPOINT=https://<account_id>.r2.cloudflarestorage.com
```

Once configured:

```bash
make backup                 # backs up locally, then rclone syncs BACKUP_PATH to BACKUP_REMOTE_PATH
make backup-list-remote     # rclone lsf $BACKUP_REMOTE_PATH inside the backup container — see what's in the bucket
make backup-restore FILE_DB=db_<ts>.sql.gz FILE_FILES=files_<ts>.tar.gz REMOTE=1
                             # fetches both files from BACKUP_REMOTE_PATH into BACKUP_PATH, then restores as usual
```

Notes:
- Remote-side retention isn't managed by these scripts — `apply_retention` only prunes
  `BACKUP_PATH` locally. If you want old backups pruned from the bucket too, set a lifecycle rule
  on the bucket itself, or point `BACKUP_REMOTE_SYNC_CMD` at a command that mirrors deletions
  (rclone's `sync` already does this: files deleted locally by retention are also removed from
  the remote on the next sync).
- `make backup-list-remote` and the `REMOTE=1` fetch step of `make backup-restore` both run
  `rclone`/`BACKUP_REMOTE_FETCH_CMD` **inside the `backup` container** (`docker compose ...
  --profile backup run --rm --no-deps ... backup ...`), regardless of `BACKUP_SCHEDULER` — so
  neither ever needs `rclone`/`rsync` installed on the host, only the `RCLONE_CONFIG_S3_*`
  credentials present in `.env` (docker-compose.prod.yml passes them into the container). This
  is separate from `scripts/backup.sh`'s own post-backup sync (`BACKUP_REMOTE_SYNC_CMD`), which
  still runs on the host when `BACKUP_SCHEDULER=host` and does need the tool in the host `PATH`.
- Because the fetch/list container always mounts the fixed `./backups` host directory (same as
  the scheduler container in `docker-compose.prod.yml`), `REMOTE=1` restores assume the default
  `BACKUP_PATH=./backups`.

## 4. Scheduling — `BACKUP_SCHEDULER=host`

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

## 5. Scheduling — `BACKUP_SCHEDULER=container`

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
  (default `BACKUP_REMOTE_SYNC_CMD` tool) + `rclone` (for S3/S3-compatible remotes — see
  "Remote storage — S3 and S3-compatible" above).
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

## 6. Restore

```bash
make backup-restore FILE_DB=backups/db_20260101_030000.sql.gz FILE_FILES=backups/files_20260101_030000.tar.gz
```

**Destructive**: overwrites the current database and the entire contents of `public_html/`.
`scripts/backup-restore.sh` prints both file paths and requires typing the literal word `yes` to
proceed (same confirmation pattern as `make nuke`) — anything else cancels. It always runs on the
host via `docker compose exec` (never inside the scheduling container). After a restore, run
`make wp-permissions` if file ownership looks wrong.

Add `REMOTE=1` to fetch both files from `BACKUP_REMOTE_PATH` into `BACKUP_PATH` first (via
`BACKUP_REMOTE_FETCH_CMD`) before restoring — pass bare filenames (not paths) for `FILE_DB`/
`FILE_FILES` in that case, e.g.:

```bash
make backup-restore FILE_DB=db_20260101_030000.sql.gz FILE_FILES=files_20260101_030000.tar.gz REMOTE=1
```
