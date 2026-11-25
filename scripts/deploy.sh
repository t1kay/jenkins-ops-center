#!/usr/bin/env bash
# Deploy 1 image tag lên 1 môi trường. Chạy trên app server (Jenkins gọi qua SSH):
#   bash /opt/app/scripts/deploy.sh <env> <image_tag>
# Yêu cầu: /opt/app/<env>/ có docker-compose.yml, nginx.conf, .env
# Kết quả: deploy OK thì ghi tag vào last_good_tag; health fail thì exit 1.
set -euo pipefail

ENV_NAME="${1:-}"
IMAGE_TAG="${2:-}"
APP_ROOT="${APP_ROOT:-/opt/app}"
HEALTH_RETRIES="${HEALTH_RETRIES:-20}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-3}"

log() { echo "[deploy][$ENV_NAME] $*"; }
die() { echo "[deploy][$ENV_NAME] ERROR: $*" >&2; exit 1; }

[[ "$ENV_NAME" =~ ^(staging|prod)$ ]] || die "ENV phải là staging hoặc prod (nhận: '$ENV_NAME')"
[[ "$IMAGE_TAG" =~ ^[A-Za-z0-9_.-]+$ ]] || die "IMAGE_TAG không hợp lệ: '$IMAGE_TAG'"

APP_DIR="$APP_ROOT/$ENV_NAME"
cd "$APP_DIR" || die "Không có thư mục $APP_DIR"
[[ -f .env ]] || die "Thiếu $APP_DIR/.env (tạo từ deploy/.env.$ENV_NAME.example)"
[[ -f docker-compose.yml ]] || die "Thiếu $APP_DIR/docker-compose.yml"

HTTP_PORT="$(grep -E '^HTTP_PORT=' .env | cut -d= -f2)"
[[ -n "$HTTP_PORT" ]] || die "Thiếu HTTP_PORT trong .env"
PREVIOUS_TAG="$(cat last_good_tag 2>/dev/null || echo none)"

log "Tag hiện tại: $PREVIOUS_TAG -> tag mới: $IMAGE_TAG"
sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=$IMAGE_TAG/" .env

log "Pull image"
docker compose --env-file .env pull app
log "docker compose up -d"
docker compose --env-file .env up -d --remove-orphans

log "Healthcheck http://localhost:$HTTP_PORT/health"
for ((i = 1; i <= HEALTH_RETRIES; i++)); do
    body="$(curl -fsS -m 3 "http://localhost:$HTTP_PORT/health" 2>/dev/null || true)"
    if [[ "$body" == *'"status":"ok"'* && "$body" == *"\"version\":\"$IMAGE_TAG\""* ]]; then
        echo "$IMAGE_TAG" > last_good_tag
        echo "$(date -Is) $IMAGE_TAG OK" >> deploy_history.log
        log "Deploy OK: $body"
        exit 0
    fi
    sleep "$HEALTH_INTERVAL"
done

echo "$(date -Is) $IMAGE_TAG FAILED" >> deploy_history.log
log "Healthcheck FAILED sau $((HEALTH_RETRIES * HEALTH_INTERVAL))s. Response cuối: ${body:-<none>}"
log "Log app gần nhất:"
docker compose --env-file .env logs --tail 50 app || true
echo "LAST_GOOD_TAG=$PREVIOUS_TAG"
die "Deploy $IMAGE_TAG lỗi. Rollback: chạy job deploy-app với ENV=$ENV_NAME, IMAGE_TAG=$PREVIOUS_TAG"
