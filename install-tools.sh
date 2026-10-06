#!/usr/bin/env bash
# Exit on command errors, undefined variables and pipeline failures.
set -Eeuo pipefail
# Print the failing line when an unexpected shell error occurs.
trap 'echo "[FAIL] install-tools line $LINENO" >&2' ERR
# Validate the architecture or required generated file before continuing.
test "$(dpkg --print-architecture)" = amd64
# Create required configuration or persistent directories if missing.
mkdir -p /etc/apt/keyrings /opt/devops /opt/jenkins
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
# Write this repository setting or report the completed operation.
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ noble main' > /etc/apt/sources.list.d/azure-cli.list
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
# Write this repository setting or report the completed operation.
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable' > /etc/apt/sources.list.d/docker.list
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
# Write this repository setting or report the completed operation.
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com noble main' > /etc/apt/sources.list.d/hashicorp.list
# Refresh package indexes for the configured signed repositories.
apt-get update
# Install the listed packages from configured repositories or a downloaded package.
apt-get install -y --no-install-recommends azure-cli docker-ce-cli docker-compose-plugin terraform
# Isolate Python DevOps dependencies in the tool virtual environment.
python3 -m venv /opt/devops
# Install Ansible and supporting Python libraries in the isolated environment.
/opt/devops/bin/pip install --no-cache-dir ansible ansible-lint yamllint requests boto3 kubernetes
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/aws.zip
# Extract the AWS CLI installer archive.
unzip -q /tmp/aws.zip -d /tmp
# Install AWS CLI v2 into its standard system location.
/tmp/aws/install
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL https://dl.k8s.io/release/stable.txt -o /tmp/kube-version
# Read the current Kubernetes release selected for kubectl.
kv=$(cat /tmp/kube-version)
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL "https://dl.k8s.io/release/${kv}/bin/linux/amd64/kubectl" -o /tmp/kubectl
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL "https://dl.k8s.io/release/${kv}/bin/linux/amd64/kubectl.sha256" -o /tmp/kubectl.sha256
# Verify the downloaded kubectl binary using its published SHA-256 checksum.
(cd /tmp; echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check)
# Place the downloaded CLI binary on PATH with executable permissions.
install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL https://api.github.com/repos/argoproj/argo-cd/releases/latest -o /tmp/argo.json
# Read the upstream Argo CD CLI release tag.
av=$(jq -er .tag_name /tmp/argo.json)
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/${av}/argocd-linux-amd64" -o /usr/local/bin/argocd
# Set executable or private-directory permissions explicitly.
chmod 755 /usr/local/bin/argocd
# Resolve Helm and code-server releases via official repositories.
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL https://api.github.com/repos/helm/helm/releases/latest -o /tmp/helm.json
# Read the upstream Helm release tag.
hv=$(jq -er .tag_name /tmp/helm.json)
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL "https://get.helm.sh/helm-${hv}-linux-amd64.tar.gz" -o /tmp/helm.tgz
# Extract the downloaded Helm release archive.
tar -xzf /tmp/helm.tgz -C /tmp
# Place the downloaded CLI binary on PATH with executable permissions.
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest -o /tmp/code.json
# Read the upstream code-server release version.
cv=$(jq -er '.tag_name | ltrimstr("v")' /tmp/code.json)
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL "https://github.com/coder/code-server/releases/download/v${cv}/code-server_${cv}_amd64.deb" -o /tmp/code.deb
# Install the listed packages from configured repositories or a downloaded package.
apt-get install -y /tmp/code.deb
# Download this package, key or version metadata over HTTPS with TLS verification.
curl -fsSL https://get.jenkins.io/war-stable/latest/jenkins.war -o /opt/jenkins/jenkins.war
# Remove only disposable build downloads and package caches to reduce image size.
rm -rf /tmp/aws /tmp/aws.zip /tmp/linux-amd64 /tmp/*.json /tmp/*.deb /tmp/*.tgz /var/lib/apt/lists/*
