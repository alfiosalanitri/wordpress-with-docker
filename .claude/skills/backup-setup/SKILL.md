---
name: backup-setup
description: Interactive, step-by-step wizard that configures this project's backup system in `.env` — retention, excluded paths, scheduler (host cron vs container), and optional remote/cloud storage (S3 or an S3-compatible provider — AWS S3, Cloudflare R2, Backblaze B2, self-hosted MinIO, Wasabi — or a plain rsync target). For each provider choice, walks the user through creating the bucket, the user/API key, and the access credentials in that provider's own console, then writes the matching `.env` values. Use when asked to set up backups, configure backup storage, connect backups to S3/cloud storage, or "guide me through backup configuration". For already-configured reference material (retention semantics, restore commands, cron examples, what each `make backup*` target does) use the `backup` skill instead — this skill is the one-time guided setup, `backup` is the ongoing reference.
---

# Backup setup wizard

Drive this as a real back-and-forth with the user — one decision at a time via `AskUserQuestion`,
not a wall of questions up front. Don't invent bucket names, keys, or endpoints; only write values
the user actually gave you. After each step, briefly explain *why* the next step matters before
asking it.

## 0. Precondition

`.env` must already exist (created by `./setup.sh`). If it's missing, stop and tell the user to
run `./setup.sh` first — this skill only edits an existing `.env`, it doesn't bootstrap the project.

## 1. Ask: where will backups run?

This matters before anything else because it decides *where* any remote-storage tooling
(`rclone`) needs to be installed.

- **`host`** — a cron entry on the host machine runs `scripts/backup.sh` directly. If the user
  later picks S3/S3-compatible storage, **`rclone` must be installed on the host itself**
  (`curl https://rclone.org/install.sh | sudo bash`, or the distro package) — the bundled `rclone`
  in `backup/Dockerfile` only exists inside the container scheduler image.
- **`container`** — the `backup` service in `docker-compose.prod.yml` (profile `backup`, started
  via `make prod-up`) runs on a schedule inside its own container, which already has `rclone`
  built in. Only available on the production stack.

Write the choice: `BACKUP_SCHEDULER=host` or `BACKUP_SCHEDULER=container`. If `container`, also ask
for the cron schedule (default `0 3 * * *`) and write `BACKUP_SCHEDULE_CRON`.

## 2. Ask: local-only backups, or also sync to a remote/cloud destination?

If **local-only**: skip to step 5 (retention/excludes).

If **remote**: continue to step 3.

## 3. Ask: which destination?

Present these options and a one-line trade-off for each (the user asked for suggestions, so
actually recommend rather than just listing):

| Option | Why you'd pick it |
|---|---|
| **AWS S3** | Industry-standard, most tooling/support; pay for storage + egress (egress adds up on large restores). |
| **Cloudflare R2** | S3-compatible API, **zero egress fees** — cheaper if you'll ever restore/download a lot. Good default recommendation for this kind of backup use case. |
| **Backblaze B2** | Usually the cheapest raw storage, free egress up to ~3x stored data/month. Great for pure "write and mostly never read" backups. |
| **Wasabi** | Flat-rate pricing, no egress fees, but has a minimum 30-day storage charge per object — less ideal for short retention windows. |
| **Self-hosted MinIO** | Free if you already run a server, full control, but you own the durability/availability (no built-in geographic redundancy unless you set it up). |
| **Other S3-compatible / plain rsync target** | Any other provider, or a plain SSH/rsync server you already have — covered generically below. |

All the S3-compatible options plug into the same `BACKUP_REMOTE_PATH`/`RCLONE_CONFIG_S3_*`
mechanism already wired up in this repo (`scripts/backup.sh`, `docker-compose.prod.yml`) — only
the values differ per provider.

## 4. Provider-specific walkthrough

Based on the answer to step 3, walk through the matching section below **in order** — bucket
first, then user/key, then note the values needed. Ask the user to come back with each value as
they get it rather than assuming they'll batch everything.

### AWS S3

1. **Bucket**: AWS Console → S3 → *Create bucket*. Pick a globally-unique name and a region.
   Leave "Block all public access" **on**.
2. **User**: IAM → Users → *Add user* → e.g. `wp-backup` → access type "Programmatic access" (no
   console login needed).
3. **Least-privilege policy** — attach this inline policy to the user (replace `BUCKET_NAME`):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       { "Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": "arn:aws:s3:::BUCKET_NAME" },
       { "Effect": "Allow", "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
         "Resource": "arn:aws:s3:::BUCKET_NAME/*" }
     ]
   }
   ```
4. **Access key**: on the user → *Security credentials* tab → *Create access key* → copy the
   Access Key ID and Secret Access Key (the secret is shown only once).
5. Note the bucket's **region** (e.g. `eu-west-1`).

Resulting values → `RCLONE_CONFIG_S3_PROVIDER=AWS`, `RCLONE_CONFIG_S3_REGION=<region>`,
`RCLONE_CONFIG_S3_ENDPOINT=` (leave empty — AWS uses its default endpoint).

### Cloudflare R2

1. **Bucket**: Cloudflare dashboard → R2 → *Create bucket*.
2. **API token**: R2 → *Manage API tokens* → *Create API token* → permission "Object Read &
   Write", **scope it to the specific bucket** (not account-wide) if the option is offered.
3. Token creation shows the Access Key ID, Secret Access Key, and the **S3 API endpoint**
   (`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`) — copy all three immediately, the secret is
   shown only once.

Resulting values → `RCLONE_CONFIG_S3_PROVIDER=Cloudflare`, `RCLONE_CONFIG_S3_ENDPOINT=https://<ACCOUNT_ID>.r2.cloudflarestorage.com`,
`RCLONE_CONFIG_S3_REGION=auto`.

### Backblaze B2

1. **Bucket**: B2 Cloud Storage → *Buckets* → *Create a Bucket* (private).
2. **Application key**: *Account* → *Application Keys* → *Add a New Application Key* → restrict
   it to that one bucket, permission "Read and Write".
3. Copy `keyID` (→ access key id) and `applicationKey` (→ secret) — shown once.
4. On the bucket's details page, note the **S3 endpoint** shown there, e.g.
   `s3.eu-central-003.backblazeb2.com` — the region segment (`eu-central-003`) is also the region
   value.

Resulting values → `RCLONE_CONFIG_S3_ENDPOINT=https://s3.<region>.backblazeb2.com`,
`RCLONE_CONFIG_S3_REGION=<region>` (same string as in the endpoint).

### Wasabi

1. **Bucket**: Wasabi console → *Buckets* → *Create Bucket* → choose a region.
2. **User**: *Access Management* → *Users* → *Create User* → programmatic access, attach a
   policy scoped to that bucket (or `WasabiFullAccess` if a custom policy isn't set up yet).
3. Create an **access key** for that user → copy the Access Key and Secret Key.
4. Note the region-specific endpoint, e.g. `s3.eu-central-1.wasabisys.com`.

Resulting values → `RCLONE_CONFIG_S3_PROVIDER=Wasabi`, `RCLONE_CONFIG_S3_ENDPOINT=https://s3.<region>.wasabisys.com`,
`RCLONE_CONFIG_S3_REGION=<region>`.

### Self-hosted MinIO

1. **Bucket**: MinIO Console (or `mc mb`) → *Buckets* → *Create Bucket*.
2. **User**: *Identity* → *Users* → *Create User* (don't reuse the root user for this) → attach a
   policy scoped to that bucket, or the built-in `readwrite` policy if scoping isn't set up yet.
3. On that user → *Service Accounts* → *Create access key* → copy the Access Key and Secret Key.
4. Note the MinIO server's URL, e.g. `https://minio.example.com:9000`.

Resulting values → `RCLONE_CONFIG_S3_PROVIDER=Minio`, `RCLONE_CONFIG_S3_ENDPOINT=https://minio.example.com:9000`,
`RCLONE_CONFIG_S3_REGION=` (usually unused for MinIO, leave empty).

### Other S3-compatible provider

Ask the user for: the S3 API **endpoint URL**, the **region** (if the provider uses one), and
whether the provider requires **path-style addressing** (some smaller/self-hosted providers do).
Bucket/user/key creation steps mirror the ones above (create a bucket, create a
scoped user or API token, generate an access key pair) — point the user at that provider's own
"S3 compatible API" or "developer" docs page for the exact console flow, since it varies.

If path-style addressing is needed, that's a 7th rclone setting
(`RCLONE_CONFIG_S3_FORCE_PATH_STYLE=true`) that isn't in this repo's default var list yet — add it
to `.env`, `.env.example`, **and** the `backup` service's `environment:` block in
`docker-compose.prod.yml` (same pattern as the six existing `RCLONE_CONFIG_S3_*` vars), otherwise
it won't reach the container scheduler.

### Plain rsync/SSH target (not S3)

If the user already has a server reachable over SSH and just wants `rsync`, skip all of the above:
set `BACKUP_REMOTE_PATH=user@host:/path/to/backups` and leave `BACKUP_REMOTE_SYNC_CMD=rsync -az`
(the default). Passwordless SSH key auth for that user must already work from wherever
`scripts/backup.sh` runs (the host, or — if `BACKUP_SCHEDULER=container` — the `backup` container
would need an SSH key mounted in, which isn't wired up by default; recommend `host` scheduling for
this path unless the user wants to extend `docker-compose.prod.yml` for it).

## 5. Write the `.env` values

For every value that is **not** a secret (bucket/prefix, provider, region, endpoint, sync/fetch
command), edit `.env` directly once the user has given them to you:

```
BACKUP_REMOTE_PATH=s3:<bucket>/<prefix>
BACKUP_REMOTE_SYNC_CMD=rclone sync
BACKUP_REMOTE_FETCH_CMD=rclone copy
RCLONE_CONFIG_S3_TYPE=s3
RCLONE_CONFIG_S3_PROVIDER=<from the provider section above>
RCLONE_CONFIG_S3_REGION=<from the provider section above, or blank>
RCLONE_CONFIG_S3_ENDPOINT=<from the provider section above, or blank for AWS>
```

For the two **secret** values (`RCLONE_CONFIG_S3_ACCESS_KEY_ID`,
`RCLONE_CONFIG_S3_SECRET_ACCESS_KEY`): don't ask the user to paste these into the chat by default —
tell them exactly which two lines in `.env` to fill in themselves. Only write them yourself if the
user explicitly pastes them and asks you to; make clear that pasting a secret into the conversation
means it will appear in this session's history.

## 6. Retention and exclusions

Ask (both optional, sensible defaults exist already):
- `BACKUP_RETENTION_DAYS` — days to keep local backups before deletion (default `7`; `0` disables
  pruning). Note this only prunes `BACKUP_PATH` locally — if the sync command is `rclone sync`,
  deletions also propagate to the remote on the next sync; `rsync -az` (no `--delete`) never
  deletes remote files.
- `BACKUP_EXCLUDE_PATHS` — space-separated paths under `public_html/` to skip (e.g. cache
  directories: `wp-content/cache wp-content/uploads/tmp`).

## 7. Wire up the scheduler

- If `BACKUP_SCHEDULER=host`: remind the user to add the cron entry themselves (nothing here does
  it automatically) — `crontab -e`:
  ```
  0 3 * * * cd /path/to/project && ./scripts/backup.sh all >> logs/backup.log 2>&1
  ```
  and, if remote storage was configured, confirm `rclone` (or `rsync`) is actually installed and
  in `PATH` on this host.
- If `BACKUP_SCHEDULER=container`: nothing else to do — `docker-compose.prod.yml` already passes
  every `BACKUP_*`/`RCLONE_CONFIG_S3_*` var into the `backup` service. Just `make prod-up` (and
  `make prod-restart` if the stack is already running and `.env` changed).

## 8. Verify end-to-end

Offer to run, and walk through the output with the user:
```bash
make backup                # creates a local backup, then syncs it to BACKUP_REMOTE_PATH if set
make backup-list-remote    # confirms the files actually landed remotely (S3/S3-compatible only)
```
If `make backup` fails on the sync step, it's almost always one of: `rclone`/`rsync` not installed
where the script is running, a wrong endpoint/region, or a bucket-scoped policy that's missing a
permission (`s3:ListBucket` on the bucket itself, not just objects, is the most commonly missed
one for AWS/Wasabi/MinIO custom policies).

For everyday operation after setup (retention behavior, restore, `REMOTE=1` restore-fetch,
container scheduling internals), point the user at the **backup** skill.
