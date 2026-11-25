# Jenkins CI/CD & Ops Automation Center

Hệ thống lấy **Jenkins làm trung tâm** cho cả CI/CD lẫn vận hành:

- **CI/CD:** push code lên GitHub, Jenkins tự lint, test, build Docker image, push lên Docker Hub rồi deploy: `develop` lên staging (tự động), `main` lên prod (có bước bấm **Approve**).
- **Ops:** backup/restore PostgreSQL, health-check, dọn ổ đĩa, deploy/rollback đều là job Jenkins, chạy theo lịch hoặc bấm nút. Lỗi thì báo về Telegram.

App được deploy là một web app Flask nhỏ (ghi chú) + PostgreSQL, chạy sau Nginx. App chỉ để có cái mà deploy, trọng tâm là phần Jenkins và script vận hành.

> Kế hoạch chi tiết và quy ước Git: [`plan.md`](plan.md). Xử lý sự cố: [`docs/RUNBOOK.md`](docs/RUNBOOK.md).

---

## Kiến trúc

```
   Developer
      │ git push
      ▼
┌─────────────┐   webhook   ┌──────────────────────────────┐
│ GitHub repo │ ──────────► │ Jenkins controller (VM #1)   │
└─────────────┘             │  - Multibranch CI/CD         │
                            │  - 5 ops job                 │
                            └──────────────┬───────────────┘
                                           │ giao việc
                                           ▼
                            ┌──────────────────────────────┐
                            │ Jenkins agent (container)    │──► Docker Hub
                            │  label: docker-agent         │
                            └──────────────┬───────────────┘
                                           │ scp script + ssh
                                           ▼
                            ┌──────────────────────────────┐
                            │ App server (VM #2)           │
                            │  staging: nginx+app+postgres │  :8081
                            │  prod   : nginx+app+postgres │  :8080
                            └──────────────────────────────┘
                                           │
               Jenkins ──── thông báo ───► Telegram
```

| Thành phần | Công nghệ |
|---|---|
| CI/CD, scheduler | Jenkins LTS (Docker), Multibranch Pipeline, Declarative Pipeline |
| App | Flask + gunicorn, PostgreSQL 16, Nginx reverse proxy |
| Đóng gói & chạy | Docker, Docker Compose (staging/prod = 2 compose project khác port) |
| Script vận hành | Bash (`set -euo pipefail`), Python (chỉ thư viện chuẩn) |
| Thông báo | Telegram Bot API (gọi từ `post { }` của Jenkins) |

---

## Danh sách job Jenkins

| Job | Loại | Kích hoạt | Parameter | File |
|---|---|---|---|---|
| `app-pipeline` | Multibranch Pipeline | Webhook khi push | — | [`Jenkinsfile`](Jenkinsfile) |
| `deploy-app` | Pipeline | Bấm tay / `app-pipeline` gọi | `ENV`, `IMAGE_TAG` | [`jobs/deploy.Jenkinsfile`](jobs/deploy.Jenkinsfile) |
| `backup-database` | Pipeline | Cron `H 2 * * *` (~2h sáng) | `ENV` (`all`/`prod`/`staging`) | [`jobs/backup.Jenkinsfile`](jobs/backup.Jenkinsfile) |
| `restore-database` | Pipeline | Bấm tay (prod phải xác nhận) | `ENV`, `BACKUP_FILE` | [`jobs/restore.Jenkinsfile`](jobs/restore.Jenkinsfile) |
| `health-check` | Pipeline | Cron `H/5 * * * *` | — | [`jobs/healthcheck.Jenkinsfile`](jobs/healthcheck.Jenkinsfile) |
| `cleanup-disk` | Pipeline | Cron `H 3 * * 0` (Chủ nhật) | — | [`jobs/cleanup.Jenkinsfile`](jobs/cleanup.Jenkinsfile) |

**Luồng theo branch của `app-pipeline`**

| Branch | Lint & Test | Build & push image | Deploy |
|---|---|---|---|
| `feature/*`, `fix/*` | ✅ | ❌ | ❌ |
| `develop` | ✅ | ✅ | Staging (tự động) |
| `main` | ✅ | ✅ | Prod (chờ bấm **Approve**, tối đa 1 giờ) |

Image được tag `<BUILD_NUMBER>-<sha7>` (vd `12-a1b2c3d`), không dùng `latest`, nên biết chính xác bản nào đang chạy và rollback được.

**Nguyên tắc**
- Logic nằm trong `scripts/`; Jenkins chỉ điều phối: `scp` script lên `/opt/app/scripts/` rồi `ssh` chạy.
- Script lỗi thì exit code ≠ 0, Jenkins đánh dấu build fail.
- Mọi thông báo đi qua `post { failure { ... } }` của Jenkins, script không tự gửi tin.
- Không có secret nào trong repo: tất cả nằm trong Jenkins Credentials.

---

## Cấu trúc repo

```
├── app/                  Flask app (/, /notes, /health)
├── tests/                pytest
├── Dockerfile            image app (non-root, gunicorn, HEALTHCHECK)
├── Jenkinsfile           CI/CD multibranch
├── deploy/               docker-compose (nginx+app+postgres), nginx.conf, .env mẫu
├── jenkins/              docker-compose Jenkins controller + agent, plugins.txt
├── jobs/                 Jenkinsfile cho 5 ops job
├── scripts/              setup_server.sh, deploy.sh, backup_db.sh, restore_db.sh,
│                         healthcheck.py, cleanup.sh
└── docs/                 RUNBOOK.md, images/
```

---

## Hướng dẫn dựng lại từ đầu

### Bước 0: Chuẩn bị
- 2 VM Ubuntu 22.04/24.04 (VirtualBox/Multipass hoặc 2 EC2), SSH được tới nhau.
  - **VM #1 – Jenkins:** 2 vCPU / 4 GB RAM, cài Docker.
  - **VM #2 – App server:** 1–2 vCPU / 2 GB RAM. Ví dụ IP `192.168.56.11`.
- Tài khoản Docker Hub (tạo access token), bot Telegram (lấy token từ @BotFather và chat id).
- Fork/clone repo này về GitHub của bạn.

### Bước 1: App server (VM #2)
Tạo SSH key cho Jenkins (trên máy bất kỳ), copy public key + script lên VM #2 rồi chạy:
```bash
ssh-keygen -t ed25519 -N "" -C jenkins-deploy -f jenkins_deploy_key
```
```bash
sudo bash scripts/setup_server.sh jenkins_deploy_key.pub
```
Script cài Docker, tạo user `deploy` (group docker), thêm key, tạo `/opt/app/{scripts,staging,prod}` và `/opt/backups/{staging,prod}`.

Tạo file `.env` cho từng môi trường (đổi password, sửa `IMAGE` thành repo Docker Hub của bạn):
```bash
sudo -u deploy cp deploy/.env.staging.example /opt/app/staging/.env
```
```bash
sudo -u deploy cp deploy/.env.prod.example /opt/app/prod/.env
```

### Bước 2: Jenkins (VM #1)
```bash
cd jenkins && cp .env.example .env
```
```bash
docker compose up -d --build controller
```
```bash
docker compose exec controller cat /var/jenkins_home/secrets/initialAdminPassword
```
1. Mở `http://<VM1>:8080`, nhập mật khẩu, chọn *Select plugins to install → None* (plugin đã cài sẵn từ `plugins.txt`), tạo user admin.
2. **Manage Jenkins → Nodes → New Node**: tên `docker-agent`, Permanent, label `docker-agent`, 2 executor, Remote root `/home/jenkins/agent`, Launch method *Launch agent by connecting it to the controller*. Đặt executor của Built-In Node = 0.
3. Copy secret của node vào `jenkins/.env` (`AGENT_SECRET=...`), đặt `DOCKER_GID=$(stat -c %g /var/run/docker.sock)`, rồi `docker compose up -d --build agent`.

### Bước 3: Credentials & biến global
**Manage Jenkins → Credentials → (global)**:

| ID | Loại | Giá trị |
|---|---|---|
| `app-server-key` | SSH Username with private key | user `deploy` + nội dung `jenkins_deploy_key` |
| `dockerhub-cred` | Username with password | username Docker Hub + access token |
| `telegram-bot-token` | Secret text | token bot |
| `telegram-chat-id` | Secret text | chat id |
| `github-token` | Username with password | username GitHub + PAT (scan repo, webhook) |

**Manage Jenkins → System → Global properties → Environment variables**:
- `DOCKER_IMAGE` = `<dockerhub-user>/jenkins-ops-app`
- `APP_SERVER` = `deploy@192.168.56.11`

### Bước 4: Tạo job
- `app-pipeline`: *New Item → Multibranch Pipeline*, Branch Source GitHub (credential `github-token`), Script Path `Jenkinsfile`, filter branch `main develop feature/* fix/*`.
- 5 ops job: *New Item → Pipeline*, *Pipeline script from SCM*, repo này, branch `*/main`, Script Path tương ứng `jobs/<tên>.Jenkinsfile` (xem bảng job ở trên). Tên job phải đúng (`deploy-app` được `app-pipeline` gọi theo tên).
- Chạy tay mỗi ops job **1 lần** để Jenkins đọc `parameters` và `triggers` (cron) trong Jenkinsfile.

### Bước 5: Webhook
GitHub repo → *Settings → Webhooks*: URL `http://<jenkins>/github-webhook/`, content type `application/json`, event *push*.
Nếu Jenkins ở máy local (GitHub không gọi vào được): dùng **ngrok**/**smee.io** chuyển tiếp, hoặc bật *Periodically scan* / Poll SCM `H/2 * * * *`.

### Bước 6: Thử
1. `deploy-app` → *Build with Parameters* `ENV=staging`, `IMAGE_TAG=<tag đã push>` → mở `http://<VM2>:8081/health`.
2. Push 1 commit lên `develop` → sau 2–3 phút staging chạy code mới (`version` trong `/health` = tag mới).
3. Merge `develop` vào `main` → bấm **Deploy** ở stage *Approve prod* → prod `:8080` cập nhật.
4. `docker stop prod-app-1` trên VM #2 → trong 5 phút Telegram báo lỗi; start lại → báo hồi phục.

---

## Đã kiểm thử những gì

Trong môi trường dựng tạm (Docker + registry local, giả lập `/opt/app/staging`):

| Hạng mục | Kết quả |
|---|---|
| `ruff check`, `pytest` (10 test) | ✅ pass |
| `shellcheck` 5 script Bash | ✅ sạch |
| Build image app, `docker compose up` staging, gọi `/`, `/notes`, `/health` | ✅ |
| `deploy.sh` tag 1 → tag 2 → tag "hỏng" | ✅ 2 lần OK; tag hỏng: exit 1, in log app + gợi ý rollback về `last_good_tag` |
| Backup → `DELETE FROM notes` → restore `latest` | ✅ dữ liệu về đủ, có file `pre-restore_*` |
| `healthcheck.py`: app chết / port không mở / disk vượt ngưỡng | ✅ đều exit 1 và ghi rõ lý do |
| `cleanup.sh` | ✅ in dung lượng trước/sau, app vẫn chạy |
| Cú pháp Groovy 6 Jenkinsfile | ✅ parse OK |

Chưa chạy được trong môi trường đó (cần hạ tầng thật): Jenkins controller với plugin, webhook GitHub, push Docker Hub, gửi Telegram.

---

## Ảnh chụp & demo

> TODO sau khi chạy trên VM thật, lưu vào `docs/images/`:
- [ ] Stage View của `app-pipeline` (develop và main có bước Approve)
- [ ] Blue Ocean
- [ ] Lịch sử build các ops job
- [ ] Tin nhắn Telegram khi health-check fail
- [ ] GIF: push code → Jenkins chạy → web cập nhật

---

## Những gì em học được / vấn đề gặp phải

- **Script chạy qua `ssh ... 'bash -s' < script.sh` bị "nuốt" mất nửa sau.** Lệnh `docker compose exec -T` bên trong đọc stdin, mà stdin lúc đó chính là phần còn lại của script, nên backup dừng giữa chừng nhưng vẫn exit 0. Cách sửa: Jenkins `scp` script lên `/opt/app/scripts/` rồi chạy `bash /opt/app/scripts/x.sh`, đồng thời thêm `</dev/null` cho lệnh `exec` không cần input.
- **`agent none` trong stage không giải phóng executor** nếu pipeline đã khai `agent` ở cấp trên cùng. Muốn bước Approve không chiếm executor thì đặt `agent none` ở cấp pipeline và khai agent cho từng stage cần.
- **Healthcheck sau deploy phải kiểm tra version**, không chỉ HTTP 200: container cũ vẫn đang trả 200 nên dễ tưởng deploy mới đã thành công. `/health` trả về `version` = image tag, `deploy.sh` so khớp với tag vừa deploy.
- **Không tin parameter đầu vào:** `IMAGE_TAG`, `BACKUP_FILE` được ghép vào lệnh SSH nên được kiểm tra bằng regex ở cả Jenkinsfile lẫn script.
- **Restore là thao tác nguy hiểm:** script luôn backup trạng thái hiện tại (`pre-restore_*`) trước khi ghi đè, prod phải bấm xác nhận.

## Hướng mở rộng
- Jenkins Shared Library cho `notifyTelegram()` và bước upload script (đang lặp ở các Jenkinsfile).
- JCasC + Job DSL để dựng lại toàn bộ Jenkins (node, credentials, job) bằng code.
- Docker Swarm để chạy nhiều replica, rolling update.
- Ansible thay cho scp/ssh khi số server tăng.
