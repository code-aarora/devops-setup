#!/usr/bin/env bash
# Exit on command errors, undefined variables and pipeline failures.
set -Eeuo pipefail
# Print the failing line when an unexpected shell error occurs.
trap 'echo "[FAIL] key generation line $LINENO" >&2' ERR
# Restrict newly generated configuration and private keys to their owner.
umask 077
# Create required configuration or persistent directories if missing.
mkdir -p "$HOME/.ssh" "$HOME/.local/share/devops/tls"
# Set executable or private-directory permissions explicitly.
chmod 700 "$HOME/.ssh"
# Preserve existing configuration or key material instead of replacing it on reruns.
if [[ ! -e "$HOME/.ssh/github_devops" ]]; then
  # Generate an Ed25519 GitHub SSH identity only when no key already exists.
  ssh-keygen -q -t ed25519 -N '' -C 'devops-laptop-github' -f "$HOME/.ssh/github_devops"
fi
# Validate the architecture or required generated file before continuing.
test -s "$HOME/.ssh/github_devops.pub"
# Preserve existing configuration or key material instead of replacing it on reruns.
if [[ ! -e "$HOME/.ssh/config" ]]; then
  # Write the service or SSH configuration using explicit values.
  printf 'Host github.com\n  User git\n  IdentityFile ~/.ssh/github_devops\n  IdentitiesOnly yes\n' > "$HOME/.ssh/config"
fi
# Set the persistent location for the localhost certificate and key.
tls="$HOME/.local/share/devops/tls"
# Preserve existing configuration or key material instead of replacing it on reruns.
if [[ ! -e "$tls/localhost.key" ]]; then
  # Generate a self-signed localhost certificate and separate TLS private key.
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' -keyout "$tls/localhost.key" -out "$tls/localhost.crt"
fi
# Write this repository setting or report the completed operation.
echo '[PASS] GitHub SSH key and local self-signed TLS certificate available; private keys were not exported.'
