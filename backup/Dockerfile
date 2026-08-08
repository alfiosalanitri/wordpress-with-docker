FROM alpine:3.20

# mariadb-client -> mariadb-dump/mariadb CLIs used by scripts/backup.sh
# rsync          -> default BACKUP_REMOTE_SYNC_CMD tool (swap for rclone here if preferred)
# tar/gzip/bash   are already part of the Alpine base image
RUN apk add --no-cache bash mariadb-client rsync

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
