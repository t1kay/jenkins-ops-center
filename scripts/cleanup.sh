#!/usr/bin/env bash
# Dọn ổ đĩa trên app server. Chạy trên app server:
#   bash /opt/app/scripts/cleanup.sh
# - Xoá container đã dừng, image không dùng cũ hơn N ngày, build cache
# - Dọn journal log cũ (nếu được cấp sudo cho journalctl, xem setup_server.sh)
# - In dung lượng trước/sau
set -euo pipefail

KEEP_IMAGE_HOURS="${KEEP_IMAGE_HOURS:-168}"   # 7 ngày
JOURNAL_DAYS="${JOURNAL_DAYS:-14}"
DISK_PATH="${DISK_PATH:-/}"

log() { echo "[cleanup] $*"; }
used_kb() { df -Pk "$DISK_PATH" | awk 'NR==2 {print $3}'; }

log "Trước khi dọn:"
df -h "$DISK_PATH"
docker system df
BEFORE="$(used_kb)"

log "Xoá container đã dừng > 24h"
docker container prune -f --filter "until=24h"

# Image đang được container dùng sẽ không bị xoá. Image cũ của app bị xoá
# vẫn pull lại được từ registry khi cần rollback.
log "Xoá image không dùng cũ hơn ${KEEP_IMAGE_HOURS}h"
docker image prune -af --filter "until=${KEEP_IMAGE_HOURS}h"

log "Xoá build cache"
docker builder prune -f

if sudo -n /usr/bin/journalctl --vacuum-time="${JOURNAL_DAYS}d" 2>/dev/null; then
    log "Đã dọn journal log cũ hơn ${JOURNAL_DAYS} ngày"
else
    log "Bỏ qua dọn journal (không có quyền sudo cho journalctl)"
fi

AFTER="$(used_kb)"
log "Sau khi dọn:"
df -h "$DISK_PATH"
log "Giải phóng được: $(( (BEFORE - AFTER) / 1024 )) MB"
