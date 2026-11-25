# RUNBOOK – xử lý sự cố

Quy ước: `<env>` là `staging` (port 8081) hoặc `prod` (port 8080). Trên app server, mọi lệnh chạy bằng user `deploy` trong `/opt/app/<env>/`:

```bash
cd /opt/app/<env> && docker compose --env-file .env ps
```

Ưu tiên xử lý bằng **job Jenkins** (có log, có lịch sử); chỉ SSH tay khi Jenkins không dùng được.

---

## 1. App chết / health-check báo lỗi

**Dấu hiệu:** Telegram `🔥 HEALTH CHECK FAILED`, `/health` trả 502/503/504 hoặc không kết nối được.

1. Xem dòng `[FAIL]` trong tin nhắn / log job `health-check` để biết env nào, lỗi gì.
2. Kiểm tra container:
   ```bash
   docker compose --env-file .env ps
   ```
   ```bash
   docker compose --env-file .env logs --tail 100 app
   ```
3. Theo từng trường hợp:
   | Triệu chứng | Xử lý |
   |---|---|
   | `app` bị Exit / restart liên tục | Xem log. Nếu do bản mới deploy → **rollback** (mục 3) |
   | `/health` trả `"db":"down"` | Xem `docker compose logs db`; disk đầy? (mục 2). Khởi động lại: `docker compose --env-file .env restart db` |
   | 502/504 từ nginx | `app` chưa lên hoặc treo: `docker compose --env-file .env restart app` |
   | Cả host không SSH được | Kiểm tra VM (console của hypervisor/cloud), mạng |
4. Xác nhận: `curl -s localhost:<port>/health` trả `"status":"ok"`; job `health-check` lần sau xanh và Telegram báo `✅ Health check OK trở lại`.

## 2. Disk đầy

**Dấu hiệu:** health-check báo `disk / xx%`, Postgres lỗi ghi, `docker pull` lỗi `no space left on device`.

1. Chạy job **`cleanup-disk`** (Build Now). Log in dung lượng trước/sau.
2. Nếu vẫn đầy, tìm thủ phạm:
   ```bash
   df -h /
   ```
   ```bash
   docker system df
   ```
   ```bash
   sudo du -xh / --max-depth=2 2>/dev/null | sort -h | tail -20
   ```
3. Các chỗ hay phình: `/opt/backups/*` (backup cũ hơn 7 ngày tự xoá; `pre-restore_*` phải xoá tay khi chắc không cần), `/var/lib/docker` (image cũ), journal log.
4. **Không xoá** volume `<env>_db-data` – đó là dữ liệu database.

## 3. Deploy lỗi → rollback

**Dấu hiệu:** Telegram `❌ Deploy <env> FAILED`, job `deploy-app` đỏ, trong log có dòng `LAST_GOOD_TAG=...`.

1. Đọc log job `deploy-app`: phần `Log app gần nhất` cho biết lý do (thiếu env, lỗi code, DB...).
2. Rollback: chạy job **`deploy-app`** với `ENV=<env>`, `IMAGE_TAG=<tag trong tin nhắn>`.
   Tag tốt gần nhất cũng có trong file trên server:
   ```bash
   cat /opt/app/<env>/last_good_tag
   ```
   ```bash
   tail /opt/app/<env>/deploy_history.log
   ```
3. Xác nhận `/health` trả `version` đúng tag cũ.
4. Sửa lỗi trên branch `fix/<tên-ngắn>` → merge `develop` → kiểm tra staging → merge `main`.

## 4. Cần restore database

**Khi nào:** dữ liệu bị xoá/hỏng do thao tác nhầm hoặc migration lỗi.

1. Xem các bản backup hiện có: chạy job **`restore-database`**, stage *Validate* sẽ liệt kê `/opt/backups/<env>/`. Hoặc:
   ```bash
   ls -lt /opt/backups/<env>/
   ```
2. Chạy **`restore-database`** với `ENV=<env>`, `BACKUP_FILE=<tên file>` hoặc `latest`. Với prod phải bấm **Restore** ở bước xác nhận.
3. Script sẽ: backup trạng thái hiện tại thành `pre-restore_<thời gian>.sql.gz` → dừng app → xoá schema `public` và nạp lại từ file → bật app → chờ `/health` OK.
4. Kiểm tra dữ liệu: `curl -s localhost:<port>/notes`.
5. Restore nhầm file? Chạy lại job với `BACKUP_FILE=pre-restore_<thời gian>.sql.gz`.

## 5. Jenkins không chạy job

| Triệu chứng | Xử lý |
|---|---|
| Job đứng ở *Waiting for next available executor* | Node `docker-agent` offline: trên VM #1 `cd jenkins && docker compose ps`, `docker compose logs agent`; kiểm tra `AGENT_SECRET` |
| Stage docker lỗi `permission denied ... docker.sock` | Sai `DOCKER_GID` trong `jenkins/.env` |
| `Host key verification failed` / `Permission denied (publickey)` | Kiểm tra credential `app-server-key` (user `deploy`) và `~deploy/.ssh/authorized_keys` |
| Push lên `develop` mà không build | Kiểm tra webhook GitHub (*Recent Deliveries*), hoặc ngrok/smee còn chạy; tạm thời *Scan Multibranch Pipeline Now* |
| Cron job không tự chạy | Job phải được chạy tay 1 lần để Jenkins đọc `triggers` trong Jenkinsfile |
| Không nhận Telegram | Kiểm tra credential `telegram-bot-token`, `telegram-chat-id`; log có dòng `WARN: ... Telegram` |
