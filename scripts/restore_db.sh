#!/usr/bin/env bash
# shellcheck disable=SC2016  # $POSTGRES_* được expand bên trong container db
# Restore PostgreSQL từ 1 file backup. Chạy trên app server:
#   bash /opt/app/scripts/restore_db.sh <env> <backup_file|latest>
# Trước khi restore sẽ tự backup trạng thái hiện tại (pre-restore) để có đường lui.
set -euo pipefail

ENV_NAME="${1:-}"
BACKUP_FILE="${2:-latest}"
APP_ROOT="${APP_ROOT:-/opt/app}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/backups}"

log() { echo "[restore][$ENV_NAME] $*"; }
die() { echo "[restore][$ENV_NAME] ERROR: $*" >&2; exit 1; }

[[ "$ENV_NAME" =~ ^(staging|prod)$ ]] || die "ENV phải là staging hoặc prod (nhận: '$ENV_NAME')"

APP_DIR="$APP_ROOT/$ENV_NAME"
BACKUP_DIR="$BACKUP_ROOT/$ENV_NAME"
cd "$APP_DIR" || die "Không có thư mục $APP_DIR"

if [[ "$BACKUP_FILE" == "latest" ]]; then
    # shellcheck disable=SC2012  # tên file do backup_db.sh tạo, không có ký tự lạ
    FILE="$(ls -1t "$BACKUP_DIR"/"${ENV_NAME}"_*.sql.gz 2>/dev/null | head -n1 || true)"
    [[ -n "$FILE" ]] || die "Không có file backup nào trong $BACKUP_DIR"
else
    # Chỉ nhận tên file nằm trong thư mục backup của env, không nhận đường dẫn
    [[ "$BACKUP_FILE" =~ ^[A-Za-z0-9_.-]+\.sql\.gz$ ]] || die "Tên file không hợp lệ: '$BACKUP_FILE'"
    FILE="$BACKUP_DIR/$BACKUP_FILE"
fi
[[ -f "$FILE" ]] || die "Không tìm thấy $FILE"
gzip -t "$FILE" || die "File backup bị lỗi: $FILE"

compose() { docker compose --env-file .env "$@"; }
psql_db() { compose exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"'; }

SAFETY="$BACKUP_DIR/pre-restore_$(date +%Y%m%d_%H%M%S).sql.gz"
log "Backup trạng thái hiện tại -> $SAFETY"
compose exec -T db sh -c 'pg_dump --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    </dev/null | gzip -9 > "$SAFETY"

log "Dừng app trong lúc restore"
compose stop app

log "Restore từ $FILE"
echo 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;' | psql_db
gunzip -c "$FILE" | psql_db >/dev/null

log "Khởi động lại app"
compose start app

HTTP_PORT="$(grep -E '^HTTP_PORT=' .env | cut -d= -f2)"
for _ in $(seq 1 15); do
    if curl -fsS -m 3 "http://localhost:$HTTP_PORT/health" >/dev/null 2>&1; then
        log "Restore OK, app healthy"
        exit 0
    fi
    sleep 2
done
die "Restore xong nhưng app không healthy. File backup trước khi restore: $SAFETY"
