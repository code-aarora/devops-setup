#!/usr/bin/env bash
# Exit on command errors, undefined variables and pipeline failures.
set -Eeuo pipefail
# Print the failing line when an unexpected shell error occurs.
trap 'echo "[FAIL] tool verification line $LINENO" >&2' ERR
# Verify git is installed and report its version; fail if the check fails.
git --version
# Verify python3 is installed and report its version; fail if the check fails.
python3 --version
# Verify ansible is installed and report its version; fail if the check fails.
ansible --version
# Verify az is installed and report its version; fail if the check fails.
az version
# Verify aws is installed and report its version; fail if the check fails.
aws --version
# Verify kubectl is installed and report its version; fail if the check fails.
kubectl version --client
# Verify helm is installed and report its version; fail if the check fails.
helm version --short
# Verify argocd is installed and report its version; fail if the check fails.
argocd version --client
# Verify terraform is installed and report its version; fail if the check fails.
terraform version
# Verify docker is installed and report its version; fail if the check fails.
docker --version
# Verify docker is installed and report its version; fail if the check fails.
docker compose version
# Verify code-server is installed and report its version; fail if the check fails.
code-server --version
# Verify java is installed and report its version; fail if the check fails.
java -version
# Verify java is installed and report its version; fail if the check fails.
java -jar /opt/jenkins/jenkins.war --version
# Write this repository setting or report the completed operation.
echo '[PASS] All Ubuntu tools verified'
