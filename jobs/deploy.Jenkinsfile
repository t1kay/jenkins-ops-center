// Job 'deploy-app': deploy 1 image tag lên staging/prod.
// Bấm tay (Build with Parameters) hoặc được 'app-pipeline' gọi.
// Rollback = chạy lại job này với IMAGE_TAG cũ (xem last_good_tag trong tin báo lỗi).
//
// Biến môi trường global: APP_SERVER  vd: deploy@192.168.56.11

pipeline {
    agent { label 'docker-agent' }

    parameters {
        choice(name: 'ENV', choices: ['staging', 'prod'], description: 'Môi trường deploy')
        string(name: 'IMAGE_TAG', defaultValue: '', description: 'Tag image, vd 12-a1b2c3d')
    }

    environment {
        APP_SERVER = "${env.APP_SERVER ?: 'deploy@192.168.56.11'}"
        SSH_OPTS   = '-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10'
    }

    options {
        timeout(time: 15, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
    }

    stages {
        stage('Validate') {
            steps {
                script {
                    if (!(params.IMAGE_TAG ==~ /[A-Za-z0-9_.-]+/)) {
                        error "IMAGE_TAG không hợp lệ: '${params.IMAGE_TAG}'"
                    }
                    currentBuild.description = "${params.ENV} ← ${params.IMAGE_TAG}"
                }
            }
        }

        stage('Upload files') {
            steps {
                sshagent(['app-server-key']) {
                    sh '''
                        scp $SSH_OPTS scripts/*.sh scripts/healthcheck.py "$APP_SERVER:/opt/app/scripts/"
                        scp $SSH_OPTS deploy/docker-compose.yml deploy/nginx.conf "$APP_SERVER:/opt/app/$ENV/"
                    '''
                }
            }
        }

        stage('Deploy') {
            steps {
                sshagent(['app-server-key']) {
                    sh 'ssh $SSH_OPTS "$APP_SERVER" bash /opt/app/scripts/deploy.sh "$ENV" "$IMAGE_TAG"'
                }
            }
        }
    }

    post {
        success {
            notifyTelegram("🚀 Deploy ${params.ENV} OK: ${params.IMAGE_TAG}\n${env.BUILD_URL}")
        }
        failure {
            script {
                def lastGood = 'không rõ'
                try {
                    sshagent(['app-server-key']) {
                        lastGood = sh(returnStdout: true,
                            script: 'ssh $SSH_OPTS "$APP_SERVER" cat "/opt/app/$ENV/last_good_tag"').trim()
                    }
                } catch (err) {
                    echo "Không đọc được last_good_tag: ${err}"
                }
                notifyTelegram("❌ Deploy ${params.ENV} FAILED: ${params.IMAGE_TAG}\n" +
                               "Rollback: chạy deploy-app với IMAGE_TAG=${lastGood}\n${env.BUILD_URL}")
            }
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
