# Plan Project: Jenkins CI/CD & Ops Automation Center

> Project tầm trung để ứng tuyển **DevOps Intern**, tập trung vào **Jenkins**.

---

## 1. Tổng quan

Xây dựng một hệ thống mà **Jenkins làm trung tâm** cho cả hai việc:

1. **CI/CD**: dev push code, Jenkins tự test, build Docker image, push lên registry rồi deploy.
2. **Vận hành (Ops)**: các tác vụ lặp lại như backup/restore database, health-check, dọn ổ đĩa đều thành job Jenkins, chạy theo lịch hoặc bấm nút.

App được deploy là một web app nhỏ (Flask/FastAPI + PostgreSQL) sau Nginx. App chỉ cần đơn giản, trọng tâm là phần Jenkins.

### Không làm trong project này
- Ansible (đã có ở project khác, ở đây dùng Bash/Python qua SSH)
- Kubernetes, Terraform
- Security scanning / DevSecOps

---

## 2. Liên hệ với JD

| Yêu cầu trong JD | Phần tương ứng trong project |
|---|---|
| Xây dựng & duy trì CI/CD bằng Jenkins | Multibranch pipeline CI/CD, webhook, Jenkinsfile trong repo |
| Script tự động hoá tác vụ lặp lại (Bash, Python) | `deploy.sh`, `backup_db.sh`, `restore_db.sh`, `healthcheck.py`, `cleanup.sh` |
| Triển khai các môi trường dev/staging/prod | `develop` → staging, `main` → prod (có bước approve) |
| Linux, mạng, lưu trữ, cơ sở dữ liệu | Linux server, Nginx reverse proxy, SSH, backup/restore PostgreSQL, giám sát disk |
| Docker | App và Jenkins đều chạy bằng Docker / Docker Compose |
| Ghi chép tài liệu kỹ thuật | `README.md`, `RUNBOOK.md` |

---

## 3. Kiến trúc

```
   Developer
      │ git push
      ▼
┌─────────────┐   webhook   ┌──────────────────────────────┐
│ GitHub repo │ ──────────► │ Jenkins controller (VM #1)   │
└─────────────┘             │  - Multibranch CI/CD         │
                            │  - 5 ops job                 │
                            └──────────────┬───────────────┘
                                           │ giao việc build
                                           ▼
                            ┌──────────────────────────────┐
                            │ Jenkins agent (container)    │──► Docker Hub
                            │  test, build & push image    │
                            └──────────────────────────────┘
                                           │ SSH + script
                                           ▼
                            ┌──────────────────────────────┐
                            │ App server (VM #2)           │
                            │  staging: nginx+app+postgres │  :8081
                            │  prod   : nginx+app+postgres │  :8080
                            └──────────────────────────────┘
                                           │
               Jenkins ──── thông báo ───► Telegram / Discord
```

**Hạ tầng tối thiểu**
- **VM #1:** Jenkins controller + agent (agent chạy dạng container), khoảng 2 vCPU / 4 GB RAM
- **VM #2:** App server, staging và prod là 2 Docker Compose project khác port, khoảng 1–2 vCPU / 2 GB RAM
- Dùng VirtualBox/Multipass trên laptop (miễn phí) hoặc 2 EC2 trên AWS

> **Lưu ý webhook:** nếu Jenkins chạy trên máy local, GitHub không gọi vào được. Dùng **ngrok** / **smee.io** để chuyển tiếp webhook, hoặc tạm dùng **Poll SCM** (`H/2 * * * *`).

---

## 4. Danh sách job Jenkins

### 4.1. CI/CD

| Job | Loại | Kích hoạt | Mô tả |
|---|---|---|---|
| `app-pipeline` | Multibranch Pipeline | Webhook khi push | Checkout → Lint → Test → Build image → Push → gọi `deploy-app` |

**Luồng theo branch**
| Branch | Test | Build & push image | Deploy |
|---|---|---|---|
| `feature/*` | ✅ | ❌ | ❌ |
| `develop` | ✅ | ✅ | Staging (tự động) |
| `main` | ✅ | ✅ | Prod (chờ bấm **Approve**) |

### 4.2. Ops jobs

| Job | Kích hoạt | Parameter | Script |
|---|---|---|---|
| `deploy-app` | Bấm tay / được `app-pipeline` gọi | `ENV` (staging/prod), `IMAGE_TAG` | `deploy.sh` |
| `backup-database` | Cron, khoảng 2h sáng hằng ngày | `ENV` | `backup_db.sh` |
| `restore-database` | Bấm tay | `ENV`, `BACKUP_FILE` | `restore_db.sh` |
| `health-check` | Cron, 5 phút/lần | — | `healthcheck.py` |
| `cleanup-disk` | Cron, Chủ nhật hằng tuần | — | `cleanup.sh` |

**Nguyên tắc chung**
- Script đơn giản, tập trung ở `scripts/`; Jenkins chỉ điều phối (gọi script qua SSH).
- Script lỗi thì **exit code ≠ 0**, Jenkins đánh dấu build fail.
- Mọi thông báo đi qua Jenkins (`post { failure { ... } }`), không rải logic gửi tin trong từng script.

---

## 5. Cấu trúc repo

```
jenkins-ops-center/
├── app/                        # Web app (Flask/FastAPI)
│   ├── main.py
│   └── requirements.txt
├── tests/                      # pytest
├── Dockerfile
├── Jenkinsfile                 # CI/CD pipeline (multibranch)
│
├── deploy/
│   ├── docker-compose.yml      # nginx + app + postgres
│   ├── nginx.conf
│   ├── .env.staging.example
│   └── .env.prod.example
│
├── jenkins/
│   ├── docker-compose.yml      # Jenkins controller + agent
│   └── plugins.txt             # danh sách plugin cần cài
│
├── jobs/                       # Jenkinsfile cho các ops job
│   ├── deploy.Jenkinsfile
│   ├── backup.Jenkinsfile
│   ├── restore.Jenkinsfile
│   ├── healthcheck.Jenkinsfile
│   └── cleanup.Jenkinsfile
│
├── scripts/
│   ├── setup_server.sh         # chạy tay 1 lần: cài Docker, tạo user deploy
│   ├── deploy.sh
│   ├── backup_db.sh
│   ├── restore_db.sh
│   ├── healthcheck.py
│   └── cleanup.sh
│
└── docs/
    ├── RUNBOOK.md              # xử lý sự cố
    └── images/                 # ảnh chụp pipeline, sơ đồ
```

---

## 6. Danh sách task

### Task 1: Chuẩn bị hạ tầng
- [ ] Tạo 2 VM, cấu hình mạng để 2 máy SSH được tới nhau
- [ ] Viết `setup_server.sh`: cài Docker, tạo user `deploy`, thêm SSH public key

### Task 2: App + Docker
- [ ] Viết app đơn giản (2–3 endpoint + `/health`) và vài test pytest
- [ ] Viết `Dockerfile` và `deploy/docker-compose.yml`, chạy tay được trên VM #2

✅ **Xong khi:** `docker compose up` chạy được app ở cả staging (:8081) và prod (:8080).

### Task 3: Dựng Jenkins
- [ ] Dựng Jenkins controller bằng Docker Compose
- [ ] Cài plugin: Pipeline, Git, GitHub, SSH Agent, Docker Pipeline, Credentials Binding
- [ ] Dựng Jenkins agent (container) và gán label `docker-agent`
- [ ] Thêm credentials (xem Mục 8)

### Task 4: Job `deploy-app`
- [ ] Viết `deploy.sh`: pull image theo tag → `docker compose up -d` → curl `/health`
- [ ] Tạo job với parameter `ENV`, `IMAGE_TAG`

✅ **Xong khi:** bấm "Build with Parameters" trong Jenkins là app được deploy lên staging.

### Task 5: CI/CD pipeline
- [ ] Viết `Jenkinsfile` ở gốc repo: Checkout → Lint → Test → Build → Push → Deploy
- [ ] Tạo Multibranch Pipeline `app-pipeline` trỏ tới repo
- [ ] Cấu hình webhook (hoặc ngrok/smee, hoặc Poll SCM)
- [ ] Logic branch: `develop` → staging, `main` → `input` approve → prod
- [ ] Tag image theo `BUILD_NUMBER` + commit SHA ngắn, không chỉ dùng `latest`

✅ **Xong khi:** push lên `develop` thì khoảng 2–3 phút sau staging chạy code mới, không cần chạm tay.

### Task 6: Backup & restore database
- [ ] `backup-database`: `pg_dump` → gzip → lưu `/opt/backups/<env>/`, xoá bản cũ hơn 7 ngày
- [ ] `restore-database`: restore từ file chọn trong parameter
- [ ] **Test restore thật**: xoá dữ liệu → restore → kiểm tra

### Task 7: Health-check & thông báo
- [ ] Tạo bot Telegram (hoặc Discord webhook), lưu token vào Jenkins credentials
- [ ] `health-check`: kiểm tra HTTP `/health`, % disk, % RAM; vượt ngưỡng thì exit 1
- [ ] Thêm `post { failure { ... } }` gửi thông báo cho mọi job

✅ **Xong khi:** tắt container app đi thì trong vòng 5 phút Telegram báo lỗi.

### Task 8: Dọn ổ đĩa
- [ ] `cleanup-disk`: `docker image prune`, xoá log cũ, báo dung lượng trước/sau

### Task 9: Rollback
- [ ] Ghi lại tag đã deploy thành công gần nhất
- [ ] Healthcheck ngay sau deploy; fail thì báo lỗi rõ ràng
- [ ] Rollback bằng cách chạy `deploy-app` với `IMAGE_TAG` cũ

### Task 10: Tài liệu & demo
- [ ] Viết `README.md` (xem checklist Mục 9)
- [ ] Viết `docs/RUNBOOK.md`: app chết / disk đầy / deploy lỗi / cần restore DB thì làm gì
- [ ] Chụp ảnh: Stage View, Blue Ocean, lịch sử build, tin nhắn Telegram
- [ ] Quay GIF demo: push code → Jenkins chạy → web cập nhật

✅ **Xong khi:** một người khác đọc README là hiểu và dựng lại được.

---

## 7. Jenkinsfile mẫu

### 7.1. CI/CD pipeline (`Jenkinsfile` ở gốc repo)

```groovy
pipeline {
    agent { label 'docker-agent' }

    environment {
        IMAGE     = 'yourdockerhub/jenkins-ops-app'
        IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
    }

    options {
        timeout(time: 20, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {
        stage('Lint & Test') {
            agent { docker { image 'python:3.12-slim' } }
            steps {
                sh 'pip install -r app/requirements.txt ruff pytest'
                sh 'ruff check app/'
                sh 'pytest -v'
            }
        }

        stage('Build & Push image') {
            when { anyOf { branch 'develop'; branch 'main' } }
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-cred',
                                 usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker build -t $IMAGE:$IMAGE_TAG .
                        docker push $IMAGE:$IMAGE_TAG
                    '''
                }
            }
        }

        stage('Deploy staging') {
            when { branch 'develop' }
            steps {
                build job: 'deploy-app', parameters: [
                    string(name: 'ENV', value: 'staging'),
                    string(name: 'IMAGE_TAG', value: env.IMAGE_TAG)
                ]
            }
        }

        stage('Approve prod') {
            when { branch 'main' }
            agent none                      // không giữ executor trong lúc chờ
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    input message: "Deploy ${IMAGE_TAG} lên PRODUCTION?", ok: 'Deploy'
                }
            }
        }

        stage('Deploy prod') {
            when { branch 'main' }
            steps {
                build job: 'deploy-app', parameters: [
                    string(name: 'ENV', value: 'prod'),
                    string(name: 'IMAGE_TAG', value: env.IMAGE_TAG)
                ]
            }
        }
    }

    post {
        always  { sh 'docker logout || true' }
        failure { echo "Pipeline FAILED: ${env.BUILD_URL}" }   // thay bằng gửi Telegram
    }
}
```

### 7.2. Ops job: `jobs/backup.Jenkinsfile`

```groovy
pipeline {
    agent any
    triggers { cron('H 2 * * *') }              // khoảng 2h sáng mỗi ngày

    parameters {
        choice(name: 'ENV', choices: ['prod', 'staging'], description: 'Môi trường cần backup')
    }

    environment { SERVER = 'deploy@192.168.56.11' }

    stages {
        stage('Backup') {
            steps {
                sshagent(['app-server-key']) {
                    sh "ssh -o StrictHostKeyChecking=no ${SERVER} 'bash -s' -- ${params.ENV} < scripts/backup_db.sh"
                }
            }
        }
    }

    post {
        success { echo "Backup ${params.ENV} OK" }
        failure { echo "Backup ${params.ENV} FAILED" }      // thay bằng gửi Telegram
    }
}
```

> Với cron trigger, lần chạy tự động sẽ dùng giá trị mặc định của parameter (`prod`).

---

## 8. Credentials cần tạo trong Jenkins

| ID | Loại | Dùng cho |
|---|---|---|
| `app-server-key` | SSH Username with private key | SSH từ Jenkins vào app server |
| `dockerhub-cred` | Username with password (dùng access token) | Push/pull image |
| `telegram-bot-token` | Secret text | Gửi thông báo |
| `telegram-chat-id` | Secret text | ID nhóm/chat nhận thông báo |
| `github-token` | Secret text / Username with password | Multibranch scan repo + webhook |

**Không bao giờ** ghi mật khẩu, token vào Jenkinsfile hay commit lên Git.

---

## 8.1. Quy ước Git

**Author**
- Mọi commit đứng tên chủ repo (`t1kay`). **Không** để Claude/AI làm author hay co-author: không dùng `user.name=Claude`, không thêm trailer `Co-Authored-By: Claude ...` hay link session vào commit message / PR.
- Cấu hình ở mức repo trước khi commit:
  ```bash
  git config user.name "t1kay"
  git config user.email "<email của bạn>"
  ```
- Kiểm tra trước khi push: `git log --format='%an <%ae>%n%b' | grep -i claude` phải không ra gì.

**Tên branch: ngắn, đơn giản, chữ thường**
| Branch | Dùng cho |
|---|---|
| `main` | Code chạy trên prod |
| `develop` | Code chạy trên staging |
| `feature/<tên-ngắn>` | Tính năng mới, vd `feature/backup`, `feature/healthcheck` |
| `fix/<tên-ngắn>` | Sửa lỗi, vd `fix/deploy-timeout` |

- Không prefix tên tool/tên người (vd `claude/...`), không chuỗi ngẫu nhiên hay số session trong tên branch.

**Commit message:** ngắn, dạng `feat: ...`, `fix: ...`, `docs: ...`, `ci: ...`.

---

## 9. Checklist README khi hoàn thành

- [ ] Một đoạn giới thiệu project đã làm được gì
- [ ] Sơ đồ kiến trúc
- [ ] Bảng danh sách job + cách kích hoạt
- [ ] Ảnh Stage View của pipeline CI/CD
- [ ] Ảnh thông báo Telegram khi có sự cố
- [ ] GIF demo push code → tự deploy
- [ ] Hướng dẫn dựng lại từ đầu (bước 1, 2, 3…)
- [ ] Mục "Những gì em học được / vấn đề gặp phải và cách giải quyết"

---

## 10. Hướng mở rộng (sau khi xong, không bắt buộc)

- **Jenkins Shared Library:** gom logic deploy/thông báo dùng chung
- **JCasC + Job DSL:** dựng lại toàn bộ Jenkins bằng code
- **Docker Swarm:** chạy app nhiều replica, rolling update (JD có nhắc tới mở rộng hạ tầng)
- **`.gitlab-ci.yml`** tương đương Jenkinsfile để biết thêm GitLab CI
- Thay Bash SSH bằng **Ansible** khi số server tăng lên
