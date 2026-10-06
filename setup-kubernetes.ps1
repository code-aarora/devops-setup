param([string]$ManifestDirectory = (Join-Path $PSScriptRoot 'manifests'))
$ErrorActionPreference = 'Stop'
function InvokeCluster([string[]]$arguments) {
    $ErrorActionPreference = 'Continue'
    & minikube -p devops-laptop kubectl -- @arguments 2>&1 | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -ne 0) { throw "Cluster kubectl failed with exit code $LASTEXITCODE" }
}
Write-Host 'Waiting for the Kubernetes node to be Ready (up to 5 minutes)...'
InvokeCluster @('wait','--for=condition=Ready','node','--all','--timeout=300s')
InvokeCluster @('get','nodes')
# Applying a Namespace manifest is idempotent and avoids treating absence as an error.
New-Item -ItemType Directory -Force -Path $ManifestDirectory | Out-Null
$namespaceFile = Join-Path $ManifestDirectory 'argocd-namespace.yaml'
Set-Content -LiteralPath $namespaceFile -Encoding ASCII -Value "apiVersion: v1`nkind: Namespace`nmetadata:`n  name: argocd"
InvokeCluster @('apply','-f',$namespaceFile)
$url = 'https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml'
$manifest = Join-Path $ManifestDirectory 'argocd-install.yaml'
$partial = "$manifest.partial"
Write-Host 'Downloading Argo CD manifest using IPv4 with retries (TLS verification enabled)...'
$ErrorActionPreference = 'Continue'
& curl.exe --ipv4 --fail --location --show-error --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 20 --max-time 120 --output $partial $url 2>&1 | ForEach-Object { Write-Host "$_" }
$downloadExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($downloadExit -ne 0) { throw "Argo CD download failed (curl exit $downloadExit). Check proxy/firewall access to raw.githubusercontent.com. No partial manifest was applied." }
if (-not (Test-Path -LiteralPath $partial) -or (Get-Item -LiteralPath $partial).Length -lt 1000) { throw 'Argo CD manifest download is empty or incomplete.' }
Move-Item -LiteralPath $partial -Destination $manifest -Force
Write-Host "Applying downloaded manifest: $manifest"
InvokeCluster @('apply','-n','argocd','--server-side','--force-conflicts','-f',$manifest)
$ErrorActionPreference = 'Continue'
$deployments = & minikube -p devops-laptop kubectl -- -n argocd get deployments -o name 2>&1
$listExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($listExit -ne 0) { throw "Unable to list Argo CD deployments: $($deployments -join ' ')" }
$deploymentNames = @($deployments | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^deployment(?:\.apps)?/[a-z0-9-]+$' })
if ($deploymentNames.Count -eq 0) { throw 'No Argo CD deployments found after applying the manifest.' }
foreach ($deployment in $deploymentNames) {
    InvokeCluster @('-n','argocd','rollout','status',$deployment,'--timeout=600s')
}
InvokeCluster @('-n','argocd','rollout','status','statefulset/argocd-application-controller','--timeout=600s')
Write-Host '[PASS] Argo CD deployments and application controller are ready.'
