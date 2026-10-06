#!/usr/bin/env bash
# Exit on command errors, undefined variables and pipeline failures.
set -Eeuo pipefail
# Print the failing line when an unexpected shell error occurs.
trap 'echo "[FAIL] entrypoint line $LINENO" >&2' ERR
# Create required configuration or persistent directories if missing.
mkdir -p /home/devops/Desktop /home/devops/.config/code-server /var/jenkins_home /workspace
# Preserve existing configuration or key material instead of replacing it on reruns.
if [[ ! -s /home/devops/.config/code-server/config.yaml ]]; then
  # Restrict newly generated configuration and private keys to their owner.
  umask 077
  # Generate a random editor login password for the first start.
  password=$(openssl rand -hex 24)
  # Write the service or SSH configuration using explicit values.
  printf 'bind-addr: 0.0.0.0:8443\nauth: password\npassword: %s\ncert: false\n' "$password" > /home/devops/.config/code-server/config.yaml
fi
# Give the service user ownership of the required persistent paths.
chown -R devops:devops /home/devops/.config /home/devops/Desktop /var/jenkins_home
# Give the service user ownership of the required persistent paths.
chown devops:devops /home/devops /workspace
# Replace the entrypoint process with the foreground service supervisor.
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
