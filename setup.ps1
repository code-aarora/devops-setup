$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$transcribing = $false
function Run([string]$exe, [string[]]$arguments) {
    # Windows PowerShell 5.1 wraps native stderr as ErrorRecords, including normal progress.
    $ErrorActionPreference = 'Continue'
    & $exe @arguments 2>&1 | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -ne 0) { throw "$exe failed with exit code $LASTEXITCODE" }
}
function Task([string]$name, [scriptblock]$action) {
    $script:step++
    Write-Host "`n[$script:step/9] $name" -ForegroundColor Cyan
    & $action
    Write-Host "[PASS] $name" -ForegroundColor Green
}
function Probe([string]$exe, [string[]]$arguments) {
    # Expected native failures must not trigger PowerShell 5.1's terminating stderr handling.
    $ErrorActionPreference = 'Continue'
    $output = & $exe @arguments 2>&1
    $code = $LASTEXITCODE
    [pscustomobject]@{ ExitCode = $code; Output = (($output | ForEach-Object { "$_" }) -join "`n") }
}
function GetEngineType([string]$output) {
    # Docker can emit startup warnings alongside the formatted result.
    $types = @($output -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -in @('linux','windows') } | Select-Object -Unique)
    if ($types.Count -eq 1) { return $types[0] }
    return ''
}
function TestEngineReady($engine) {
    return ($engine.ExitCode -eq 0 -and (GetEngineType $engine.Output) -in @('linux','windows'))
}
function RefreshPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    foreach ($p in @("$env:ProgramFiles\Docker\Docker\resources\bin", "$env:ProgramFiles\Git\cmd", "$env:LOCALAPPDATA\Microsoft\WinGet\Links")) {
        if (Test-Path -LiteralPath $p) { $env:Path += ";$p" }
    }
}
function InstallTool([string]$id, [string]$command) {
    if (Get-Command $command -ErrorAction SilentlyContinue) { Write-Host "$command already installed"; return }
    Run 'winget' @('install','--id',$id,'--exact','--source','winget','--accept-source-agreements','--accept-package-agreements')
    RefreshPath
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$id installed but $command is unavailable. Open a new terminal and rerun." }
}
$step = 0
try {
    $location = Read-Host 'Enter an absolute local disk folder for persistent DevOps files (Enter = .\data)'
    if ([string]::IsNullOrWhiteSpace($location)) { $location = Join-Path $root 'data' }
    if (-not [IO.Path]::IsPathRooted($location)) { throw 'Use an absolute disk folder such as D:\DevOpsData.' }
    $data = [IO.Path]::GetFullPath($location)
    if ($data.StartsWith('\\')) { throw 'Use a local disk, not a network share.' }
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    Start-Transcript -Path (Join-Path $root 'log.txt') -Append | Out-Null
    $transcribing = $true
    Write-Host "Persistent folder: $data"
    Task 'Verify Windows prerequisites' {
        if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'This setup requires Windows x64.' }
        if ((Get-CimInstance Win32_OperatingSystem).ProductType -ne 1) { throw 'Docker Desktop requires a supported Windows client laptop, not Windows Server.' }
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'Install Microsoft App Installer (winget) from Microsoft Store, then rerun.' }
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $admin) { throw 'Right-click setup.bat and Run as administrator using your normal Windows account.' }
    }
    Task 'Enable WSL 2 features' {
        $changed = $false
        foreach ($feature in @('Microsoft-Windows-Subsystem-Linux','VirtualMachinePlatform')) {
            if ((Get-WindowsOptionalFeature -Online -FeatureName $feature).State -ne 'Enabled') {
                Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
                $changed = $true
            }
        }
        if ($changed) { throw 'REBOOT REQUIRED: Windows features enabled. Restart Windows and rerun setup.bat.' }
        Run 'wsl.exe' @('--update')
        Run 'wsl.exe' @('--set-default-version','2')
    }
    Task 'Install Windows Docker, Git, Kubernetes tools and VS Code' {
        RefreshPath
        InstallTool 'Git.Git' 'git'
        InstallTool 'Docker.DockerDesktop' 'docker'
        InstallTool 'Kubernetes.kubectl' 'kubectl'
        InstallTool 'Kubernetes.minikube' 'minikube'
        InstallTool 'Microsoft.VisualStudioCode' 'code'
        Run 'git' @('--version')
    }
    Task 'Verify Docker Linux engine and Compose' {
        if ($env:DOCKER_API_VERSION) {
            Write-Host "Clearing forced Docker API version $env:DOCKER_API_VERSION for this setup process so Docker can negotiate."
            Remove-Item Env:DOCKER_API_VERSION
        }
        $engine = Probe 'docker' @('info','--format','{{.OSType}}')
        if ($engine.Output -match '(?i)manually paused') { throw 'Docker Desktop is paused. Open its tray menu or Dashboard, resume Docker Desktop, then rerun setup.bat.' }
        if (-not (TestEngineReady $engine)) {
            Write-Host "Docker is not ready: $($engine.Output)"
            $desktop = @("$env:ProgramFiles\Docker\Docker\Docker Desktop.exe", "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $desktop) { throw 'Docker Desktop application not found. Install Docker Desktop; a Docker CLI alone is insufficient.' }
            Start-Process -FilePath $desktop -WindowStyle Hidden
            Write-Host 'Complete Docker Desktop first-run prompts and select the WSL 2 Linux backend.'
            $ready = $false
            for ($i=0; $i -lt 60; $i++) {
                $engine = Probe 'docker' @('info','--format','{{.OSType}}')
                if ($engine.Output -match '(?i)manually paused') { throw 'Docker Desktop is paused. Open its tray menu or Dashboard, resume Docker Desktop, then rerun setup.bat.' }
                if (TestEngineReady $engine) { $ready=$true; break }
                if ($i % 6 -eq 0) { Write-Host "Waiting for Docker Linux engine ($($i * 5)/300 seconds)... Last response: $($engine.Output)" }
                Start-Sleep -Seconds 5
            }
            if (-not $ready) {
                foreach ($diagnostic in @(@('version'),@('context','show'))) {
                    $result = Probe 'docker' $diagnostic
                    Write-Host "Docker diagnostic: $($result.Output)"
                }
                throw "Docker engine unavailable after 5 minutes. Last error: $($engine.Output). Use Docker Desktop > Troubleshoot > Restart Docker Desktop, wait for Engine running, and rerun. If it still returns HTTP 500, restart Windows and check Docker Desktop diagnostics."
            }
        }
        Write-Host "Docker engine response: $($engine.Output)"
        $os = GetEngineType $engine.Output
        if ($os -eq 'windows') { throw 'Docker reports a Windows engine. Switch Docker Desktop to Linux containers and rerun.' }
        if ($os -ne 'linux') { throw "Docker returned an unexpected engine response: $($engine.Output). Run docker info --format '{{.OSType}}' and check Docker Desktop status." }
        Write-Host 'Docker Linux engine verified.'
        Run 'docker' @('compose','version')
    }
    Task 'Set environment and persistent directories' {
        foreach ($dir in @('home','jenkins','workspace')) { New-Item -ItemType Directory -Force -Path (Join-Path $data $dir) | Out-Null }
        [Environment]::SetEnvironmentVariable('DEVOPS_DATA_DIR',$data,'User')
        $env:DEVOPS_DATA_DIR = $data.Replace('\','/')
        # User PATH is preserved in full; avoid setx truncation.
        $userPath = [Environment]::GetEnvironmentVariable('Path','User')
        $dockerBin = "$env:ProgramFiles\Docker\Docker\resources\bin"
        if (($userPath -split ';') -notcontains $dockerBin) { [Environment]::SetEnvironmentVariable('Path',(([string]$userPath).TrimEnd(';')+';'+$dockerBin),'User') }
        $saved = @{DataDirectory=$data} | ConvertTo-Json
        Set-Content -LiteralPath (Join-Path $root 'setup-state.json') -Value $saved
    }
    Task 'Build and start Ubuntu DevOps container' {
        Run 'docker' @('compose','--progress','plain','-f',(Join-Path $root 'compose.yaml'),'build')
        Run 'docker' @('compose','-f',(Join-Path $root 'compose.yaml'),'up','-d','--wait','--wait-timeout','300')
        Run 'docker' @('exec','devops-ubuntu','bash','/usr/local/bin/verify-tools')
    }
    Task 'Start Kubernetes and install Argo CD' {
        Run 'minikube' @('start','-p','devops-laptop','--driver=docker','--cpus=2','--memory=4096')
        Run 'kubectl' @('--context=devops-laptop','get','nodes')
        $namespace = Probe 'kubectl' @('--context=devops-laptop','get','namespace','argocd','--ignore-not-found','-o','name')
        if ($namespace.ExitCode -ne 0) { throw "Kubernetes namespace check failed: $($namespace.Output)" }
        if ([string]::IsNullOrWhiteSpace($namespace.Output)) { Run 'kubectl' @('--context=devops-laptop','create','namespace','argocd') }
        Run 'kubectl' @('--context=devops-laptop','apply','-n','argocd','--server-side','--force-conflicts','-f','https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml')
        Run 'kubectl' @('--context=devops-laptop','-n','argocd','rollout','status','deployment/argocd-server','--timeout=300s')
    }
    Task 'Generate GitHub SSH key and local TLS certificate' {
        Run 'docker' @('exec','-u','devops','devops-ubuntu','bash','/usr/local/bin/create-keys')
        Run 'docker' @('cp','devops-ubuntu:/home/devops/.ssh/github_devops.pub',(Join-Path $root 'github_devops.pub'))
    }
    Task 'Write access guide on Ubuntu Desktop and Windows' {
        Run 'docker' @('cp',(Join-Path $root 'ACCESS.md'),'devops-ubuntu:/home/devops/Desktop/DEVOPS-ACCESS.md')
        Run 'docker' @('exec','chown','devops:devops','/home/devops/Desktop/DEVOPS-ACCESS.md')
        Copy-Item -LiteralPath (Join-Path $root 'ACCESS.md') -Destination (Join-Path $root 'DEVOPS-ACCESS.md') -Force
    }
    Write-Host "`nSUCCESS: See DEVOPS-ACCESS.md for login and GitHub registration steps." -ForegroundColor Green
} catch {
    Write-Host "`n[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Fix the reported task and rerun. Existing data and keys are preserved.'
    exit 1
} finally {
    if ($transcribing) {
        Stop-Transcript | Out-Null
        if ($data -and $data -ne $root) { Copy-Item -LiteralPath (Join-Path $root 'log.txt') -Destination (Join-Path $data 'log.txt') -Force }
    }
}
