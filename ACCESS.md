# DevOps laptop access and settings

Ubuntu is a headless container. This file is placed at `/home/devops/Desktop/DEVOPS-ACCESS.md` and copied to the Windows setup folder as `DEVOPS-ACCESS.md`.

| Service | URL / setting | Login |
| --- | --- | --- |
| Jenkins | http://localhost:8080 | Complete the setup wizard; fetch initial password below |
| VS Code compatible browser editor (code-server) | http://localhost:8443 | Fetch generated password below |
| Argo CD | https://localhost:8081 after starting port forwarding | admin; fetch initial password below |
| Kubernetes | Windows context `devops-laptop` | `kubectl --context=devops-laptop get nodes` |
| GitHub | https://github.com/settings/keys | Register `github_devops.pub` from the Windows setup folder |

Run these commands in Windows PowerShell. Passwords are deliberately excluded from this document and setup logs.

```powershell
docker exec -it -u devops devops-ubuntu bash
docker exec devops-ubuntu cat /var/jenkins_home/secrets/initialAdminPassword
docker exec devops-ubuntu cat /home/devops/.config/code-server/config.yaml
kubectl --context=devops-laptop -n argocd port-forward svc/argocd-server 8081:443 --address=127.0.0.1
```

Keep the forwarding command open in its own terminal. In a second terminal:

```powershell
$encoded = kubectl --context=devops-laptop -n argocd get secret argocd-initial-admin-secret -o 'jsonpath={.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Argo CD uses a self-signed certificate initially. Change the admin password after login. Jenkins setup lets you install plugins and create an administrator; do not disable its authentication.

Inside the Ubuntu shell:

```bash
az login --use-device-code
aws configure sso
git config --global user.name 'Your Name'
git config --global user.email 'you@example.com'
ssh -i ~/.ssh/github_devops -T git@github.com
```

Compare GitHub's host fingerprint with https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints before accepting it. A successful GitHub SSH authentication reports success but exits with code 1 because GitHub offers no shell. Registration of the public key is required before authentication works.

Python/Ansible virtual environment: `/opt/devops` (already on PATH). Java: `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64`. Jenkins: `JENKINS_HOME=/var/jenkins_home`. Workspace: `/workspace`. Home and cloud config: `/home/devops`. Windows persistent root: user environment variable `DEVOPS_DATA_DIR` and `setup-state.json`.

GitHub private key: `/home/devops/.ssh/github_devops`; public key: same path plus `.pub`. The automated key has no passphrase; protect the selected disk folder and add one with `ssh-keygen -p -f ~/.ssh/github_devops` if desired. Existing keys are preserved. Existing SSH config is preserved; use `-i` explicitly if it does not contain this identity.

Local TLS files: `/home/devops/.local/share/devops/tls/localhost.key` and `localhost.crt`. These are separate from GitHub SSH authentication and are generated but not automatically applied to services. To use TLS for code-server, change `cert: false` in its config to `cert: /home/devops/.local/share/devops/tls/localhost.crt` and add `cert-key: /home/devops/.local/share/devops/tls/localhost.key`, then restart the container. The editor URL becomes https://localhost:8443. A self-signed certificate requires explicit local trust.

Ubuntu Docker CLI is installed without a daemon/socket. Kubernetes credentials remain on Windows; use Windows kubectl for the local cluster. The Ubuntu CLI can access separately configured remote clusters. Jenkins jobs needing Docker or the local Kubernetes cluster require a deliberately configured agent/credentials.
