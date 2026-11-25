# Jenkins agent (label: docker-agent)
# - docker CLI: build/push image, chạy stage trong container (agent { docker ... })
# - openssh-client: các ops job SSH vào app server
# - curl: gửi thông báo Telegram
FROM jenkins/inbound-agent:latest-jdk17

USER root
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:27-cli /usr/local/libexec/docker/cli-plugins/docker-buildx \
     /usr/local/libexec/docker/cli-plugins/docker-buildx

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

USER jenkins
