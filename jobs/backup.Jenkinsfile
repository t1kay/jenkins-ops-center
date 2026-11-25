// Job 'backup-database': pg_dump -> gzip -> /opt/backups/<env>/, giữ 7 ngày.
// Chạy theo lịch khoảng 2h sáng mỗi ngày (lần tự động dùng giá trị mặc định 'all').

pipeline {
    agent { label 'docker-agent' }

    triggers { cron('H 2 * * *') }

    parameters {
        choice(name: 'ENV', choices: ['all', 'prod', 'staging'], description: 'Môi trường cần backup')
    }

    environment {
        APP_SERVER = "${env.APP_SERVER ?: 'deploy@192.168.56.11'}"
        SSH_OPTS   = '-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10'
        TARGETS    = "${params.ENV == 'all' ? 'prod staging' : params.ENV}"
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
    }

    stages {
        stage('Upload scripts') {
            steps {
                sshagent(['app-server-key']) {
                    sh 'scp $SSH_OPTS scripts/*.sh scripts/healthcheck.py "$APP_SERVER:/opt/app/scripts/"'
                }
            }
        }

        stage('Backup') {
            steps {
                sshagent(['app-server-key']) {
                    sh '''
                        for e in $TARGETS; do
                            ssh $SSH_OPTS "$APP_SERVER" bash /opt/app/scripts/backup_db.sh "$e"
                        done
                    '''
                }
            }
        }
    }

    post {
        success { echo "Backup ${env.TARGETS} OK" }
        failure { notifyTelegram("❌ Backup DB (${env.TARGETS}) FAILED\n${env.BUILD_URL}") }
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
