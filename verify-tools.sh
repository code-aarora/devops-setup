#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FAIL] tool verification line $LINENO" >&2' ERR
git --version
python3 --version
ansible --version
az version
aws --version
kubectl version --client
helm version --short
argocd version --client
terraform version
docker --version
docker compose version
code-server --version
java -version
java -jar /opt/jenkins/jenkins.war --version
echo '[PASS] All Ubuntu tools verified'
