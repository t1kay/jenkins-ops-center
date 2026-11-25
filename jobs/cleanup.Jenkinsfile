// Job 'cleanup-disk': dọn ổ đĩa app server mỗi Chủ nhật (khoảng 3h sáng).

pipeline {
    agent { label 'docker-agent' }

    triggers { cron('H 3 * * 0') }

    environment {
        APP_SERVER = "${env.APP_SERVER ?: 'deploy@192.168.56.11'}"
        SSH_OPTS   = '-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timestamps()
    }

    stages {
        stage('Cleanup') {
            steps {
                sshagent(['app-server-key']) {
                    sh '''#!/bin/bash
                        set -o pipefail
                        scp $SSH_OPTS scripts/cleanup.sh "$APP_SERVER:/opt/app/scripts/"
                        ssh $SSH_OPTS "$APP_SERVER" bash /opt/app/scripts/cleanup.sh | tee cleanup.log
                    '''
                }
            }
        }
    }

    post {
        success {
            script {
                def freed = readFile('cleanup.log').readLines().find { it.contains('Giải phóng được') } ?: ''
                echo "Cleanup OK. ${freed}"
            }
        }
        failure { notifyTelegram("❌ Cleanup disk FAILED\n${env.BUILD_URL}") }
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
