FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH=/opt/devops/bin:/home/devops/.local/bin:$PATH JENKINS_HOME=/var/jenkins_home
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl wget gnupg git openssh-client openssl unzip zip jq yq vim nano less sudo make build-essential dnsutils iputils-ping netcat-openbsd rsync python3 python3-pip python3-venv pipx openjdk-21-jdk supervisor nodejs npm tini && rm -rf /var/lib/apt/lists/*
COPY install-tools.sh /tmp/install-tools.sh
RUN sed -i 's/\r$//' /tmp/install-tools.sh && bash /tmp/install-tools.sh && rm /tmp/install-tools.sh
RUN useradd -m -s /bin/bash devops && echo 'devops ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/devops && chmod 440 /etc/sudoers.d/devops && mkdir -p /var/jenkins_home /workspace && chown devops:devops /var/jenkins_home /workspace
COPY entrypoint.sh verify-tools.sh create-keys.sh /usr/local/bin/
RUN for f in entrypoint verify-tools create-keys; do mv /usr/local/bin/$f.sh /usr/local/bin/$f; sed -i 's/\r$//' /usr/local/bin/$f; chmod +x /usr/local/bin/$f; done
COPY supervisord.conf /etc/supervisor/conf.d/devops.conf
EXPOSE 8080 8443
WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
