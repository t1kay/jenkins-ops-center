// Job 'restore-database': restore DB từ 1 file backup. Chỉ chạy bằng tay.
// Script tự backup trạng thái hiện tại (pre-restore_*.sql.gz) trước khi ghi đè.

pipeline {
    agent { label 'docker-agent' }

    parameters {
        choice(name: 'ENV', choices: ['staging', 'prod'], description: 'Môi trường cần restore')
        string(name: 'BACKUP_FILE', defaultValue: 'latest',
               description: "Tên file trong /opt/backups/<env>/ (vd staging_20260101_020000.sql.gz) hoặc 'latest'")
    }

    environment {
        APP_SERVER = "${env.APP_SERVER ?: 'deploy@192.168.56.11'}"
        SSH_OPTS   = '-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10'
    }

    options {
        timeout(time: 45, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
    }

    stages {
        stage('Validate') {
            steps {
                script {
                    if (!(params.BACKUP_FILE ==~ /latest|[A-Za-z0-9_.-]+\.sql\.gz/)) {
                        error "BACKUP_FILE không hợp lệ: '${params.BACKUP_FILE}'"
                    }
                    currentBuild.description = "${params.ENV} ← ${params.BACKUP_FILE}"
                }
                sshagent(['app-server-key']) {
                    sh '''
                        scp $SSH_OPTS scripts/*.sh scripts/healthcheck.py "$APP_SERVER:/opt/app/scripts/"
                        echo "Các bản backup hiện có của $ENV:"
                        ssh $SSH_OPTS "$APP_SERVER" ls -lt "/opt/backups/$ENV/"
                    '''
                }
            }
        }

        stage('Confirm prod') {
            when { expression { params.ENV == 'prod' } }
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    input message: "Restore PROD từ '${params.BACKUP_FILE}'? Dữ liệu hiện tại sẽ bị ghi đè.",
                          ok: 'Restore'
                }
            }
        }

        stage('Restore') {
            steps {
                sshagent(['app-server-key']) {
                    sh 'ssh $SSH_OPTS "$APP_SERVER" bash /opt/app/scripts/restore_db.sh "$ENV" "$BACKUP_FILE"'
                }
            }
        }
    }

    post {
        success { notifyTelegram("♻️ Restore DB ${params.ENV} OK từ ${params.BACKUP_FILE}\n${env.BUILD_URL}") }
        failure { notifyTelegram("❌ Restore DB ${params.ENV} FAILED (${params.BACKUP_FILE})\n${env.BUILD_URL}") }
    }
}

def notifyTelegram(String message) {
    try {
        withCredentials([string(credentialsId: 'telegram-bot-token', variable: 'TG_TOKEN'),
                         string(credentialsId: 'telegram-chat-id', variable: 'TG_CHAT_ID')]) {
            withEnv(["TG_TEXT=${message}"]) {
                sh '''
                    curl -fsS -m 10 -o /dev/null -X POST \
                        "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
                        --data-urlencode "chat_id=${TG_CHAT_ID}" \
                        --data-urlencode "text=${TG_TEXT}" \
                    || echo "WARN: gửi Telegram thất bại"
                '''
            }
        }
    } catch (err) {
        echo "WARN: không gửi được Telegram: ${err}"
    }
}
