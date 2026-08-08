#!/usr/bin/env bash
set -euo pipefail

echo "${BACKUP_SCHEDULE_CRON:-0 3 * * *} /scripts/backup.sh all >> /proc/1/fd/1 2>&1" > /etc/crontabs/root

exec crond -f -l 8
