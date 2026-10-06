# Use Ubuntu 24.04 as the tool environment base.
FROM ubuntu:24.04
# Define noninteractive build behavior and runtime tool/service environment.
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
# Define noninteractive build behavior and runtime tool/service environment.
ENV PATH=/opt/devops/bin:/home/devops/.local/bin:$PATH JENKINS_HOME=/var/jenkins_home
# Propagate failures inside piped Bash build commands.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Install base language, networking, build and service-supervision dependencies; clear the package cache.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl wget gnupg git openssh-client openssl unzip zip jq yq vim nano less sudo make build-essential dnsutils iputils-ping netcat-openbsd rsync python3 python3-pip python3-venv pipx openjdk-21-jdk supervisor nodejs npm tini && rm -rf /var/lib/apt/lists/*
# Add the upstream CLI installer to the image build.
COPY install-tools.sh /tmp/install-tools.sh
# Normalize Windows line endings, run installation and remove the temporary script.
RUN sed -i 's/\r$//' /tmp/install-tools.sh && bash /tmp/install-tools.sh && rm /tmp/install-tools.sh
# Create the devops user, local lab sudo access and writable service/workspace folders.
RUN useradd -m -s /bin/bash devops && echo 'devops ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/devops && chmod 440 /etc/sudoers.d/devops && mkdir -p /var/jenkins_home /workspace && chown devops:devops /var/jenkins_home /workspace
# Copy startup, verification and key-generation helpers into the image.
COPY entrypoint.sh verify-tools.sh create-keys.sh /usr/local/bin/
# Normalize helper line endings and make their extensionless entrypoints executable.
RUN for f in entrypoint verify-tools create-keys; do mv /usr/local/bin/$f.sh /usr/local/bin/$f; sed -i 's/\r$//' /usr/local/bin/$f; chmod +x /usr/local/bin/$f; done
# Install the service manager configuration for Jenkins and the editor.
COPY supervisord.conf /etc/supervisor/conf.d/devops.conf
# Declare the service ports; Compose controls loopback publication on Windows.
EXPOSE 8080 8443
# Set the default interactive shell directory to the persistent workspace.
WORKDIR /workspace
# Use tini for signal handling and execute the service entrypoint.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
