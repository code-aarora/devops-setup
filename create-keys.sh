#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FAIL] key generation line $LINENO" >&2' ERR
umask 077
mkdir -p "$HOME/.ssh" "$HOME/.local/share/devops/tls"
chmod 700 "$HOME/.ssh"
if [[ ! -e "$HOME/.ssh/github_devops" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C 'devops-laptop-github' -f "$HOME/.ssh/github_devops"
fi
test -s "$HOME/.ssh/github_devops.pub"
if [[ ! -e "$HOME/.ssh/config" ]]; then
  printf 'Host github.com\n  User git\n  IdentityFile ~/.ssh/github_devops\n  IdentitiesOnly yes\n' > "$HOME/.ssh/config"
fi
tls="$HOME/.local/share/devops/tls"
if [[ ! -e "$tls/localhost.key" ]]; then
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' -keyout "$tls/localhost.key" -out "$tls/localhost.crt"
fi
echo '[PASS] GitHub SSH key and local self-signed TLS certificate available; private keys were not exported.'
