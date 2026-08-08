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

# Loaded as plain KEY=VALUE (not `source`d) since values like BACKUP_SCHEDULE_CRON
# contain spaces/asterisks that aren't valid shell syntax.
if [[ -f "$REPO_ROOT/.env" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* || "$key" == "UID" || "$key" == "GID" ]] && continue
    [[ -n "${!key+x}" ]] && continue # an already-exported value (e.g. from the caller) wins
    export "$key=$value"
  done < "$REPO_ROOT/.env"
fi

: "${MYSQL_USER:?MYSQL_USER not set — check .env}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD not set — check .env}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE not set — check .env}"

FILE_DB="${1:?Usage: $0 <db_backup.sql.gz> <files_backup.tar.gz>}"
FILE_FILES="${2:?Usage: $0 <db_backup.sql.gz> <files_backup.tar.gz>}"

[[ -f "$FILE_DB" ]] || error "Database backup not found: $FILE_DB"
[[ -f "$FILE_FILES" ]] || error "Files backup not found: $FILE_FILES"

cd "$REPO_ROOT"

warn "This will OVERWRITE the current database and public_html/ contents."
echo "  Database dump: $FILE_DB"
echo "  Files archive: $FILE_FILES"
read -rp "Type 'yes' to confirm: " confirm
[[ "$confirm" == "yes" ]] || error "Cancelled."

info "Restoring database..."
gzip -dc "$FILE_DB" | docker compose exec -T db mariadb \
  -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"
success "Database restored."

info "Restoring files..."
mkdir -p public_html
tar xzf "$FILE_FILES" -C public_html --strip-components=1
success "Files restored."

success "Restore completed. Run 'make wp-permissions' if file ownership looks wrong."
