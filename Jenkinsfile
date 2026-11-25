// CI/CD pipeline cho Multibranch job 'app-pipeline'
//   feature/*, fix/* : lint + test
//   develop          : lint + test -> build & push image -> deploy staging
//   main             : lint + test -> build & push image -> chờ Approve -> deploy prod
//
// Cấu hình qua biến môi trường global (Manage Jenkins > System > Global properties):
//   DOCKER_IMAGE  vd: yourdockerhub/jenkins-ops-app

pipeline {
    // agent none: chỉ chiếm executor ở stage cần, không giữ executor lúc chờ Approve
    agent none

    environment {
        IMAGE = "${env.DOCKER_IMAGE ?: 'yourdockerhub/jenkins-ops-app'}"
    }

    options {
        timeout(time: 90, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timestamps()
    }

    stages {
        stage('Lint & Test') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    label 'docker-agent'
                    args '-e HOME=/tmp'
                }
            }
            steps {
                sh '''
                    python -m venv /tmp/venv
                    . /tmp/venv/bin/activate
                    pip install -q -r app/requirements.txt ruff pytest
                    ruff check app/ tests/ scripts/
                    pytest -v --junitxml=reports/junit.xml
                '''
            }
            post {
                always { junit allowEmptyResults: true, testResults: 'reports/junit.xml' }
            }
        }

        stage('Build & Push image') {
            when { anyOf { branch 'develop'; branch 'main' } }
            agent { label 'docker-agent' }
            steps {
                script {
                    // Tag theo build number + commit SHA ngắn, không dùng 'latest'
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
                    currentBuild.description = "image ${env.IMAGE_TAG}"
                }
                withCredentials([usernamePassword(credentialsId: 'dockerhub-cred',
                                 usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker build --pull --build-arg APP_VERSION="$IMAGE_TAG" -t "$IMAGE:$IMAGE_TAG" .
                        docker push "$IMAGE:$IMAGE_TAG"
                    '''
                }
            }
            post {
                always {
                    sh 'docker logout || true'
                    sh 'docker image rm "$IMAGE:$IMAGE_TAG" || true'
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
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    input message: "Deploy ${env.IMAGE_TAG} lên PRODUCTION?", ok: 'Deploy'
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
        failure {
            script {
                node('docker-agent') {
                    notifyTelegram("❌ ${env.JOB_NAME} #${env.BUILD_NUMBER} FAILED\n${env.BUILD_URL}")
                }
            }
        }
        fixed {
            script {
                node('docker-agent') {
                    notifyTelegram("✅ ${env.JOB_NAME} #${env.BUILD_NUMBER} đã xanh trở lại\n${env.BUILD_URL}")
                }
            }
        }
    }
}

// Gửi tin Telegram. Lỗi gửi tin không làm fail build.
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
