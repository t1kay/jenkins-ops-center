#!/usr/bin/env bash
# shellcheck disable=SC2016  # $POSTGRES_* được expand bên trong container db
# Backup PostgreSQL của 1 môi trường. Chạy trên app server:
#   bash /opt/app/scripts/backup_db.sh <env>
# pg_dump | gzip -> /opt/backups/<env>/<env>_YYYYmmdd_HHMMSS.sql.gz, xoá bản cũ hơn N ngày.
set -euo pipefail

ENV_NAME="${1:-}"
APP_ROOT="${APP_ROOT:-/opt/app}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

log() { echo "[backup][$ENV_NAME] $*"; }
die() { echo "[backup][$ENV_NAME] ERROR: $*" >&2; exit 1; }

[[ "$ENV_NAME" =~ ^(staging|prod)$ ]] || die "ENV phải là staging hoặc prod (nhận: '$ENV_NAME')"

APP_DIR="$APP_ROOT/$ENV_NAME"
BACKUP_DIR="$BACKUP_ROOT/$ENV_NAME"
mkdir -p "$BACKUP_DIR"
cd "$APP_DIR" || die "Không có thư mục $APP_DIR"

FILE="$BACKUP_DIR/${ENV_NAME}_$(date +%Y%m%d_%H%M%S).sql.gz"
TMP="$FILE.part"
trap 'rm -f "$TMP"' EXIT

log "pg_dump -> $FILE"
docker compose --env-file .env exec -T db \
    sh -c 'pg_dump --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    </dev/null | gzip -9 > "$TMP"

gzip -t "$TMP" || die "File backup bị lỗi"
[[ "$(gunzip -c "$TMP" | head -c 1 | wc -c)" -eq 1 ]] || die "Backup rỗng"
mv "$TMP" "$FILE"
log "OK: $(du -h "$FILE" | cut -f1)"

log "Xoá backup cũ hơn $RETENTION_DAYS ngày"
find "$BACKUP_DIR" -maxdepth 1 -name "${ENV_NAME}_*.sql.gz" -type f -mtime "+$RETENTION_DAYS" -print -delete

log "Danh sách backup hiện có:"
ls -1t "$BACKUP_DIR"
