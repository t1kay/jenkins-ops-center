// Job 'health-check': 5 phút/lần kiểm tra /health của prod + staging, % disk, % RAM.
// Lỗi -> Telegram báo mỗi lần fail; hết lỗi -> báo 'đã hồi phục' 1 lần.

pipeline {
    agent { label 'docker-agent' }

    triggers { cron('H/5 * * * *') }

    environment {
        APP_SERVER = "${env.APP_SERVER ?: 'deploy@192.168.56.11'}"
        SSH_OPTS   = '-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10'
    }

    options {
        timeout(time: 5, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '100'))
        timestamps()
    }

    stages {
        stage('Health check') {
            steps {
                sshagent(['app-server-key']) {
                    sh '''#!/bin/bash
                        set -o pipefail
                        scp $SSH_OPTS scripts/healthcheck.py "$APP_SERVER:/opt/app/scripts/"
                        ssh $SSH_OPTS "$APP_SERVER" python3 /opt/app/scripts/healthcheck.py \
                            --url http://localhost:8080/health \
                            --url http://localhost:8081/health \
                            --disk-threshold 85 --mem-threshold 90 \
                        | tee healthcheck.log
                    '''
                }
            }
        }
    }

    post {
        failure {
            script {
                def detail = fileExists('healthcheck.log') ?
                    readFile('healthcheck.log').readLines().findAll { it.startsWith('[FAIL]') }.join('\n') :
                    'không SSH được tới app server'
                notifyTelegram("🔥 HEALTH CHECK FAILED\n${detail ?: 'xem log'}\n${env.BUILD_URL}")
            }
        }
        fixed {
            notifyTelegram("✅ Health check OK trở lại\n${env.BUILD_URL}")
        }
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
