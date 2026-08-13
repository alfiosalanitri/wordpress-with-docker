FROM alpine:3.20

# mariadb-client -> mariadb-dump/mariadb CLIs used by scripts/backup.sh
# rsync          -> default BACKUP_REMOTE_SYNC_CMD tool
# rclone         -> powers S3 / S3-compatible remotes (BACKUP_REMOTE_PATH=s3:...) — see the backup skill
# tar/gzip/bash   are already part of the Alpine base image
RUN apk add --no-cache bash mariadb-client rsync rclone

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
