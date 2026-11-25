#!/usr/bin/env bash
# Chuẩn bị app server (VM #2). Chạy tay 1 lần bằng root:
#   sudo bash setup_server.sh /path/to/jenkins_deploy_key.pub
# - Cài Docker + compose plugin, python3, curl
# - Tạo user 'deploy' (thuộc group docker), thêm SSH public key của Jenkins
# - Tạo thư mục /opt/app/<env> và /opt/backups/<env>
set -euo pipefail

DEPLOY_USER="deploy"
PUBKEY_FILE="${1:-}"
ENVS=(staging prod)

log() { echo "[setup] $*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Cần chạy bằng root (sudo)." >&2
    exit 1
fi
if [[ -z "$PUBKEY_FILE" || ! -f "$PUBKEY_FILE" ]]; then
    echo "Usage: $0 <ssh_public_key_file>" >&2
    exit 1
fi

log "Cài gói cơ bản"
apt-get update -y
apt-get install -y ca-certificates curl gzip python3

if ! command -v docker >/dev/null 2>&1; then
    log "Cài Docker"
    curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
    log "Tạo user $DEPLOY_USER"
    useradd --create-home --shell /bin/bash "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"

log "Thêm SSH key cho $DEPLOY_USER"
SSH_DIR="/home/$DEPLOY_USER/.ssh"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$SSH_DIR"
touch "$SSH_DIR/authorized_keys"
if ! grep -qxF "$(cat "$PUBKEY_FILE")" "$SSH_DIR/authorized_keys"; then
    cat "$PUBKEY_FILE" >> "$SSH_DIR/authorized_keys"
fi
chown "$DEPLOY_USER:$DEPLOY_USER" "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"

log "Tạo thư mục app & backup"
install -d -m 755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" /opt/app /opt/backups /opt/app/scripts
for env in "${ENVS[@]}"; do
    install -d -m 750 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/opt/app/$env" "/opt/backups/$env"
done

# cleanup.sh được phép dọn journal log mà không cần full sudo
echo "$DEPLOY_USER ALL=(root) NOPASSWD: /usr/bin/journalctl --vacuum-time=*" \
    > /etc/sudoers.d/deploy-cleanup
chmod 440 /etc/sudoers.d/deploy-cleanup
visudo -cf /etc/sudoers.d/deploy-cleanup

log "Xong. Việc còn lại:"
for env in "${ENVS[@]}"; do
    echo "  - Tạo /opt/app/$env/.env từ deploy/.env.$env.example (đổi POSTGRES_PASSWORD)"
done
