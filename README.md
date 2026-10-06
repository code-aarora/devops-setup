# Windows laptop DevOps setup

`setup.bat` launches the PowerShell installer and preserves its exit code. Keep all supplied files in this folder. It verifies or installs Windows tools, builds Ubuntu 24.04 with DevOps utilities, starts Jenkins and a VS Code compatible web editor, creates a Minikube Kubernetes cluster, installs Argo CD, and generates GitHub SSH and local TLS keys.

## Requirements and first run

Supported Windows 10/11 x64 client with hardware virtualization enabled, Microsoft App Installer (`winget`), administrator access, internet access to official package repositories, and Docker Desktop eligibility/licensing. Windows Server and ARM are not supported by this package. Suggested laptop capacity: 16 GB RAM and 40 GB free disk. Reserve at least 8 GB RAM for Docker Desktop; Minikube requests 4 GB/2 CPUs in addition to Ubuntu services.

1. Right-click `setup.bat`, select **Run as administrator**, using your usual Windows account.
2. At the disk-folder prompt, enter an absolute folder such as `D:\DevOpsData`. Press Enter to use `data` next to the scripts. Prefer a local folder outside OneDrive for credentials and performance. The Windows-side report remains in this setup folder.
3. If WSL features were enabled, restart Windows and run the batch again. No automatic reboot occurs. If an installer requests a reboot, complete it and rerun.
4. Complete Docker Desktop's first-run/license prompts when shown, using its WSL 2 backend and Linux containers.
5. Allow downloads and the Docker build to finish. The first build can take considerable time. Open `DEVOPS-ACCESS.md` when all tasks pass.

The installer changes Windows optional features, installs software with winget, adds Docker's bin directory to the user PATH without truncating existing values, and persists `DEVOPS_DATA_DIR`. Other installer PATH entries are respected. Open a new terminal to see persisted environment changes. It does not configure cloud accounts or upload keys to GitHub automatically.

## Files and tools

| File | Purpose |
| --- | --- |
| setup.bat / setup.ps1 | Interactive launcher; nine checked tasks, error handling, disk prompt, environment, log |
| setup-kubernetes.ps1 | Matching Minikube kubectl, node-readiness wait, retrying IPv4 manifest download and Argo CD rollout checks |
| Dockerfile / install-tools.sh | Ubuntu image and official tool download/repository installation |
| compose.yaml | Loopback-only services and persistent bind mounts |
| entrypoint.sh / supervisord.conf | Start and supervise Jenkins and code-server |
| verify-tools.sh | Check each installed CLI, Java and Jenkins versions |
| create-keys.sh | Preserve or create SSH and self-signed TLS keys |
| ACCESS.md | Source guide copied to Ubuntu Desktop and Windows |
| setup-state.json | Selected data-folder record generated at runtime |
| github_devops.pub | Public SSH key copied from Ubuntu after setup |
| log.txt | Appended task and command output from each setup run |

Windows installs/verifies Docker Desktop, Git, kubectl, Minikube and desktop VS Code. Ubuntu includes Git, Azure CLI, AWS CLI v2, Ansible, ansible-lint, Python/pip/venv, kubectl, Helm, Argo CD CLI, Terraform, Docker CLI/Compose, Java 21, Jenkins, code-server, Node.js/npm, make/compiler tools, jq/yq, curl/wget, OpenSSH/OpenSSL, editors and networking utilities. `code-server` provides the VS Code compatible experience inside headless Ubuntu; Microsoft's desktop VS Code is installed on Windows. Argo CD's server runs in Kubernetes, as required by its architecture. There is no graphical Ubuntu desktop; the requested Desktop file lives in its conventional directory.

No finite package list covers every DevOps product. These tools provide a general local development baseline. Ubuntu runs as a local lab with sudo available; ports bind only to Windows localhost. Docker socket access is intentionally not granted to Ubuntu/Jenkins because it would give control over the host Docker engine.

## Expected screen output and results

Each task prints `[1/9] ...` through `[9/9] ...`, command output and `[PASS]`. Failed commands cause `[FAIL]`, a nonzero exit code and a rerun instruction; later tasks do not run. Reboot requirements also return failure with an explicit explanation. Success ends with `SUCCESS` and batch exit code 0.

Expected checks: Docker reports Linux; Compose reports its version; Ubuntu verification prints tool versions and `[PASS] All Ubuntu tools verified`; Kubernetes reports a Ready node; Argo CD deployment rollout succeeds. Ubuntu services must pass HTTP health checks before continuing. No passwords/private keys are printed by the setup. `log.txt` in this folder records runtime task output and is copied to the selected disk folder after completion or failure. The disk prompt occurs before logging so logging uses a valid selected folder.

Persistent files are in `<selected folder>/home`, `/jenkins`, and `/workspace`. The home includes Desktop guide, cloud profiles, editor config and keys; Jenkins includes jobs/plugins/config. Docker image/layer storage remains managed by Docker Desktop, not the selected folder. To move Docker's virtual disk, use Docker Desktop's supported storage settings separately. Do not change the selected folder between reruns unless intentionally starting a new home/Jenkins environment.

## Daily operation (Windows PowerShell)

Run from this setup folder. If the current terminal does not yet have the new environment:

```powershell
$env:DEVOPS_DATA_DIR = (Get-Content .\setup-state.json | ConvertFrom-Json).DataDirectory.Replace('\','/')
docker compose up -d --wait --wait-timeout 300
docker exec -it -u devops devops-ubuntu bash
minikube start -p devops-laptop --driver=docker
kubectl --context=devops-laptop get pods -A
docker compose logs --timestamps 2>&1 | Tee-Object -FilePath .\log.txt -Append
```

Setup logs capture installation output; service runtime output remains in Docker logs. The last command collects it in `log.txt`. For live monitoring use `docker compose logs -f --timestamps` and Ctrl+C to stop following. Log files can grow; archive them periodically. Do not log commands that display credentials.

```powershell
# Stop services and cluster; preserve all disk data
docker compose stop
minikube stop -p devops-laptop
# Rebuild installed tools after reviewing upstream changes
docker compose --progress plain build --no-cache
docker compose up -d --wait --wait-timeout 300
```

Downloads resolve current stable releases at build/run time; this is not a version-locked production environment. GitHub API rate limits can fail a build; wait and retry. kubectl and Minikube's bundled Kubernetes may have different release versions; keep kubectl within the supported one-minor version skew for your cluster.

## GitHub and TLS

The requested GitHub integration uses an **Ed25519 SSH key**, not an SSL key. Setup generates both, copies only the public SSH key to Windows, and provides registration and authentication steps in the access guide. Private keys stay in the persistent Ubuntu home (which is a Windows disk bind mount). Protect that disk folder and exclude credentials from Git, shared folders and backups without encryption. The self-signed localhost TLS certificate expires after 365 days and is not configured on Jenkins or Argo CD automatically. GitHub webhooks require a separately reachable HTTPS endpoint and webhook secret; localhost URLs cannot receive GitHub webhooks.

## Troubleshooting and reruns

- WSL failure: enable virtualization in BIOS/UEFI, apply Windows updates, reboot, run `wsl --status`, then rerun.
- Docker timeout: finish Desktop setup, verify `docker info`, ensure Linux containers, then rerun. The script waits up to five minutes and reports progress every 30 seconds. Missing-engine errors are treated as retryable during startup rather than stopping PowerShell immediately.
- Docker HTTP 500: readiness requires both a successful exit and a recognized engine type; server-error responses are retried. The script clears a forced `DOCKER_API_VERSION` in its own process to allow API negotiation. If errors persist, use Docker Desktop > Troubleshoot > Restart Docker Desktop, wait for Engine running, then rerun. Restart Windows if necessary. No factory reset or data deletion is required by this script.
- Port already used: free localhost ports 8080/8443, or change the host side of `compose.yaml` ports and the guide together. 8081 is used only during Argo CD port forwarding.
- Container failure: `docker compose logs --timestamps`; verify Docker memory/disk allocation. Jenkins startup or package network downloads can take longer on slow hardware.
- Kubernetes/Argo failure: check `minikube status -p devops-laptop` and `kubectl --context=devops-laptop -n argocd get pods`. Reuse the same profile on rerun.
- Argo CD manifest connection reset: setup now downloads with Windows curl using IPv4, verified TLS and five retries before applying the local file. It waits for Ready nodes and uses `minikube -p devops-laptop kubectl -- ...` to match the cluster version. Downloads are saved in `manifests/`. If retries fail, check VPN/proxy/firewall access to `raw.githubusercontent.com`; do not disable TLS verification. All setup helper output is included in the main transcript.
- Permission issues: use a local disk accessible to your Windows account and Docker Desktop. Do not use another administrator's identity.
- Existing `devops-ubuntu` container owned by another project: choose a different container name consistently before proceeding; do not delete unrelated containers.
- Existing Git/CLI installation found on PATH is reused. No version upgrade is forced. Reruns preserve keys and service data but reapply the current stable Argo CD manifests.

## Official references

- https://docs.docker.com/desktop/setup/install/windows-install/
- https://minikube.sigs.k8s.io/docs/drivers/docker/
- https://kubernetes.io/docs/tasks/tools/
- https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux
- https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- https://www.jenkins.io/doc/book/installing/linux/
- https://argo-cd.readthedocs.io/en/stable/getting_started/
- https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent

The files are supplied for execution on your laptop. Static validation does not establish successful downloads, installation, service readiness, or cloud/GitHub authentication; those are checked during execution.
