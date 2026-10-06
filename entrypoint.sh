#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FAIL] entrypoint line $LINENO" >&2' ERR
mkdir -p /home/devops/Desktop /home/devops/.config/code-server /var/jenkins_home /workspace
if [[ ! -s /home/devops/.config/code-server/config.yaml ]]; then
  umask 077
  password=$(openssl rand -hex 24)
  printf 'bind-addr: 0.0.0.0:8443\nauth: password\npassword: %s\ncert: false\n' "$password" > /home/devops/.config/code-server/config.yaml
fi
chown -R devops:devops /home/devops/.config /home/devops/Desktop /var/jenkins_home
chown devops:devops /home/devops /workspace
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
