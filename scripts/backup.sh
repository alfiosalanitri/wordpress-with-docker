#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Colors
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Only present on the host — inside the backup container env vars are passed
# explicitly by docker-compose.prod.yml, so there's nothing to load here.
# Loaded as plain KEY=VALUE (not `source`d) since values like BACKUP_SCHEDULE_CRON
# or BACKUP_REMOTE_SYNC_CMD contain spaces/asterisks that aren't valid shell syntax.
if [[ -f "$REPO_ROOT/.env" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* || "$key" == "UID" || "$key" == "GID" ]] && continue
    [[ -n "${!key+x}" ]] && continue # an already-exported value (e.g. from the caller) wins
    export "$key=$value"
  done < "$REPO_ROOT/.env"
fi

BACKUP_PATH="${BACKUP_PATH:-./backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_EXCLUDE_PATHS="${BACKUP_EXCLUDE_PATHS:-}"
BACKUP_REMOTE_PATH="${BACKUP_REMOTE_PATH:-}"
BACKUP_REMOTE_SYNC_CMD="${BACKUP_REMOTE_SYNC_CMD:-rsync -az}"

: "${MYSQL_USER:?MYSQL_USER not set — check .env}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD not set — check .env}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE not set — check .env}"

MODE="${1:-all}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP_PATH"

# Running inside the backup container (docker-compose.prod.yml) vs on the host.
if [[ -f /.dockerenv ]]; then
  IN_CONTAINER=true
  FILES_SRC="${FILES_SRC:-/var/www/html}"
else
  IN_CONTAINER=false
  FILES_SRC="${FILES_SRC:-$REPO_ROOT/public_html}"
fi

backup_db() {
  local dest="$BACKUP_PATH/db_${TIMESTAMP}.sql.gz"
  info "Dumping database ${MYSQL_DATABASE}..."
  if [[ "$IN_CONTAINER" == "true" ]]; then
    mariadb-dump -h "${DB_HOST:-db}" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
      | gzip > "$dest"
  else
    (cd "$REPO_ROOT" && docker compose exec -T db mariadb-dump \
      -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE") | gzip > "$dest"
  fi
  success "Database backup saved: $dest"
}

backup_files() {
  local dest="$BACKUP_PATH/files_${TIMESTAMP}.tar.gz"
  [[ -d "$FILES_SRC" ]] || error "Files source not found: $FILES_SRC"
  info "Archiving files from ${FILES_SRC}..."
  local base_dir exclude_args=()
  base_dir="$(basename "$FILES_SRC")"
  for p in $BACKUP_EXCLUDE_PATHS; do
    exclude_args+=(--exclude="$base_dir/$p")
  done
  tar czf "$dest" "${exclude_args[@]}" -C "$(dirname "$FILES_SRC")" "$base_dir"
  success "Files backup saved: $dest"
}

apply_retention() {
  [[ "$BACKUP_RETENTION_DAYS" -gt 0 ]] || return 0
  info "Applying retention: deleting backups older than ${BACKUP_RETENTION_DAYS} days..."
  find "$BACKUP_PATH" -maxdepth 1 -type f \( -name 'db_*.sql.gz' -o -name 'files_*.tar.gz' \) \
    -mtime "+${BACKUP_RETENTION_DAYS}" -print -delete
}

sync_remote() {
  [[ -n "$BACKUP_REMOTE_PATH" ]] || return 0
  local cmd_bin
  cmd_bin="$(awk '{print $1}' <<< "$BACKUP_REMOTE_SYNC_CMD")"
  command -v "$cmd_bin" >/dev/null 2>&1 \
    || error "BACKUP_REMOTE_SYNC_CMD tool '$cmd_bin' not found in PATH."
  info "Syncing $BACKUP_PATH to remote $BACKUP_REMOTE_PATH via: $BACKUP_REMOTE_SYNC_CMD"
  $BACKUP_REMOTE_SYNC_CMD "$BACKUP_PATH" "$BACKUP_REMOTE_PATH"
  success "Remote sync completed."
}

case "$MODE" in
  all)   backup_db; backup_files ;;
  db)    backup_db ;;
  files) backup_files ;;
  *)     error "Unknown mode: $MODE (expected all|db|files)" ;;
esac

apply_retention
sync_remote
success "Backup completed."
