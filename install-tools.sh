#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FAIL] install-tools line $LINENO" >&2' ERR
test "$(dpkg --print-architecture)" = amd64
mkdir -p /etc/apt/keyrings /opt/devops /opt/jenkins
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ noble main' > /etc/apt/sources.list.d/azure-cli.list
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable' > /etc/apt/sources.list.d/docker.list
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com noble main' > /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y --no-install-recommends azure-cli docker-ce-cli docker-compose-plugin terraform
python3 -m venv /opt/devops
/opt/devops/bin/pip install --no-cache-dir ansible ansible-lint yamllint requests boto3 kubernetes
curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/aws.zip
unzip -q /tmp/aws.zip -d /tmp
/tmp/aws/install
curl -fsSL https://dl.k8s.io/release/stable.txt -o /tmp/kube-version
kv=$(cat /tmp/kube-version)
curl -fsSL "https://dl.k8s.io/release/${kv}/bin/linux/amd64/kubectl" -o /tmp/kubectl
curl -fsSL "https://dl.k8s.io/release/${kv}/bin/linux/amd64/kubectl.sha256" -o /tmp/kubectl.sha256
(cd /tmp; echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check)
install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
curl -fsSL https://api.github.com/repos/argoproj/argo-cd/releases/latest -o /tmp/argo.json
av=$(jq -er .tag_name /tmp/argo.json)
curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/${av}/argocd-linux-amd64" -o /usr/local/bin/argocd
chmod 755 /usr/local/bin/argocd
# Resolve Helm and code-server releases via official repositories.
curl -fsSL https://api.github.com/repos/helm/helm/releases/latest -o /tmp/helm.json
hv=$(jq -er .tag_name /tmp/helm.json)
curl -fsSL "https://get.helm.sh/helm-${hv}-linux-amd64.tar.gz" -o /tmp/helm.tgz
tar -xzf /tmp/helm.tgz -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest -o /tmp/code.json
cv=$(jq -er '.tag_name | ltrimstr("v")' /tmp/code.json)
curl -fsSL "https://github.com/coder/code-server/releases/download/v${cv}/code-server_${cv}_amd64.deb" -o /tmp/code.deb
apt-get install -y /tmp/code.deb
curl -fsSL https://get.jenkins.io/war-stable/latest/jenkins.war -o /opt/jenkins/jenkins.war
rm -rf /tmp/aws /tmp/aws.zip /tmp/linux-amd64 /tmp/*.json /tmp/*.deb /tmp/*.tgz /var/lib/apt/lists/*
