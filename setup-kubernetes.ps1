# Purpose: Wait for Kubernetes readiness, download Argo CD reliably and verify its rollouts.
param([string]$ManifestDirectory = (Join-Path $PSScriptRoot 'manifests'))
$ErrorActionPreference = 'Stop'
# Use the kubectl release matching the named Minikube cluster and check its exit code.
function InvokeCluster([string[]]$arguments) {
    $ErrorActionPreference = 'Continue'
    & minikube -p devops-laptop kubectl -- @arguments 2>&1 | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -ne 0) { throw "Cluster kubectl failed with exit code $LASTEXITCODE" }
}
Write-Host 'Waiting for the Kubernetes node to be Ready (up to 5 minutes)...'
# Block until every cluster node reports Ready or the timeout expires.
InvokeCluster @('wait','--for=condition=Ready','node','--all','--timeout=300s')
# Display the node state after the readiness check.
InvokeCluster @('get','nodes')
# Applying a Namespace manifest is idempotent and avoids treating absence as an error.
# Create the required disk directory without deleting existing contents.
New-Item -ItemType Directory -Force -Path $ManifestDirectory | Out-Null
# Choose the local path for the small namespace manifest.
$namespaceFile = Join-Path $ManifestDirectory 'argocd-namespace.yaml'
# Write the generated configuration or manifest to the selected path.
Set-Content -LiteralPath $namespaceFile -Encoding ASCII -Value "apiVersion: v1`nkind: Namespace`nmetadata:`n  name: argocd"
# Create or reconcile the Argo CD namespace idempotently.
InvokeCluster @('apply','-f',$namespaceFile)
$url = 'https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml'
# Choose the local path for the fully downloaded Argo CD manifest.
$manifest = Join-Path $ManifestDirectory 'argocd-install.yaml'
# Use a separate temporary download file so partial content cannot be applied.
$partial = "$manifest.partial"
Write-Host 'Downloading Argo CD manifest using IPv4 with retries (TLS verification enabled)...'
$ErrorActionPreference = 'Continue'
# Download through IPv4 with verified TLS, bounded requests and retries for transient failures.
& curl.exe --ipv4 --fail --location --show-error --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 20 --max-time 120 --output $partial $url 2>&1 | ForEach-Object { Write-Host "$_" }
$downloadExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($downloadExit -ne 0) { throw "Argo CD download failed (curl exit $downloadExit). Check proxy/firewall access to raw.githubusercontent.com. No partial manifest was applied." }
if (-not (Test-Path -LiteralPath $partial) -or (Get-Item -LiteralPath $partial).Length -lt 1000) { throw 'Argo CD manifest download is empty or incomplete.' }
# Promote the completed manifest download only after successful validation.
Move-Item -LiteralPath $partial -Destination $manifest -Force
Write-Host "Applying downloaded manifest: $manifest"
# Apply the complete local Argo CD manifest to the cluster.
InvokeCluster @('apply','-n','argocd','--server-side','--force-conflicts','-f',$manifest)
$ErrorActionPreference = 'Continue'
# List deployment resource names so each can be checked without an unsupported all flag.
$deployments = & minikube -p devops-laptop kubectl -- -n argocd get deployments -o name 2>&1
$listExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($listExit -ne 0) { throw "Unable to list Argo CD deployments: $($deployments -join ' ')" }
$deploymentNames = @($deployments | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^deployment(?:\.apps)?/[a-z0-9-]+$' })
if ($deploymentNames.Count -eq 0) { throw 'No Argo CD deployments found after applying the manifest.' }
# Check all discovered deployments individually.
foreach ($deployment in $deploymentNames) {
    # Wait for this controller rollout to finish before reporting installation success.
    InvokeCluster @('-n','argocd','rollout','status',$deployment,'--timeout=600s')
}
# Wait for this controller rollout to finish before reporting installation success.
InvokeCluster @('-n','argocd','rollout','status','statefulset/argocd-application-controller','--timeout=600s')
Write-Host '[PASS] Argo CD deployments and application controller are ready.'
