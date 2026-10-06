# Purpose: Provision Windows tools, Ubuntu services, Kubernetes and access files with checked tasks.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$transcribing = $false
# Run a native command, display its output and reject a nonzero exit code.
function Run([string]$exe, [string[]]$arguments) {
    # Windows PowerShell 5.1 wraps native stderr as ErrorRecords, including normal progress.
    $ErrorActionPreference = 'Continue'
    & $exe @arguments 2>&1 | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -ne 0) { throw "$exe failed with exit code $LASTEXITCODE" }
}
# Print the task number and report success only after its actions complete.
function Task([string]$name, [scriptblock]$action) {
    $script:step++
    Write-Host "`n[$script:step/9] $name" -ForegroundColor Cyan
    & $action
    Write-Host "[PASS] $name" -ForegroundColor Green
}
# Capture a native status response without terminating on expected startup errors.
function Probe([string]$exe, [string[]]$arguments) {
    # Expected native failures must not trigger PowerShell 5.1's terminating stderr handling.
    $ErrorActionPreference = 'Continue'
    $output = & $exe @arguments 2>&1
    $code = $LASTEXITCODE
    [pscustomobject]@{ ExitCode = $code; Output = (($output | ForEach-Object { "$_" }) -join "`n") }
}
# Extract the recognized engine type from output that may contain warnings.
function GetEngineType([string]$output) {
    # Docker can emit startup warnings alongside the formatted result.
    $types = @($output -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -in @('linux','windows') } | Select-Object -Unique)
    if ($types.Count -eq 1) { return $types[0] }
    return ''
}
# Accept readiness only when the command succeeds and reports a known engine type.
function TestEngineReady($engine) {
    return ($engine.ExitCode -eq 0 -and (GetEngineType $engine.Output) -in @('linux','windows'))
}
# Reload installed PATH entries so newly installed commands work in this process.
function RefreshPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    foreach ($p in @("$env:ProgramFiles\Docker\Docker\resources\bin", "$env:ProgramFiles\Git\cmd", "$env:LOCALAPPDATA\Microsoft\WinGet\Links")) {
        if (Test-Path -LiteralPath $p) { $env:Path += ";$p" }
    }
}
# Reuse an existing executable or install and verify its exact winget package.
function InstallTool([string]$id, [string]$command) {
    if (Get-Command $command -ErrorAction SilentlyContinue) { Write-Host "$command already installed"; return }
    # Install the named Windows package and accept its source/package terms.
    Run 'winget' @('install','--id',$id,'--exact','--source','winget','--accept-source-agreements','--accept-package-agreements')
    RefreshPath
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$id installed but $command is unavailable. Open a new terminal and rerun." }
}
$step = 0
try {
    # Prompt for the persistent local disk folder used by container data.
    $location = Read-Host 'Enter an absolute local disk folder for persistent DevOps files (Enter = .\data)'
    if ([string]::IsNullOrWhiteSpace($location)) { $location = Join-Path $root 'data' }
    if (-not [IO.Path]::IsPathRooted($location)) { throw 'Use an absolute disk folder such as D:\DevOpsData.' }
    # Resolve the selected storage location into an absolute path.
    $data = [IO.Path]::GetFullPath($location)
    if ($data.StartsWith('\\')) { throw 'Use a local disk, not a network share.' }
    # Create the required disk directory without deleting existing contents.
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    # Append screen and command output to the setup log.
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
        # Check both WSL and Virtual Machine Platform before proceeding.
        foreach ($feature in @('Microsoft-Windows-Subsystem-Linux','VirtualMachinePlatform')) {
            if ((Get-WindowsOptionalFeature -Online -FeatureName $feature).State -ne 'Enabled') {
                # Enable the required Windows feature without automatically restarting.
                Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
                $changed = $true
            }
        }
        if ($changed) { throw 'REBOOT REQUIRED: Windows features enabled. Restart Windows and rerun setup.bat.' }
        # Update WSL or select its version-2 backend before Docker setup.
        Run 'wsl.exe' @('--update')
        # Update WSL or select its version-2 backend before Docker setup.
        Run 'wsl.exe' @('--set-default-version','2')
    }
    Task 'Install Windows Docker, Git, Kubernetes tools and VS Code' {
        RefreshPath
        # Verify or install this Windows application using its winget package ID.
        InstallTool 'Git.Git' 'git'
        # Verify or install this Windows application using its winget package ID.
        InstallTool 'Docker.DockerDesktop' 'docker'
        # Verify or install this Windows application using its winget package ID.
        InstallTool 'Kubernetes.kubectl' 'kubectl'
        # Verify or install this Windows application using its winget package ID.
        InstallTool 'Kubernetes.minikube' 'minikube'
        # Verify or install this Windows application using its winget package ID.
        InstallTool 'Microsoft.VisualStudioCode' 'code'
        # Verify the installed Git executable by displaying its version.
        Run 'git' @('--version')
    }
    Task 'Verify Docker Linux engine and Compose' {
        if ($env:DOCKER_API_VERSION) {
            Write-Host "Clearing forced Docker API version $env:DOCKER_API_VERSION for this setup process so Docker can negotiate."
            # Remove only the process-level API override so Docker negotiates with its server.
            Remove-Item Env:DOCKER_API_VERSION
        }
        # Read the Docker engine status and retain diagnostics for startup retries.
        $engine = Probe 'docker' @('info','--format','{{.OSType}}')
        if ($engine.Output -match '(?i)manually paused') { throw 'Docker Desktop is paused. Open its tray menu or Dashboard, resume Docker Desktop, then rerun setup.bat.' }
        if (-not (TestEngineReady $engine)) {
            Write-Host "Docker is not ready: $($engine.Output)"
            $desktop = @("$env:ProgramFiles\Docker\Docker\Docker Desktop.exe", "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $desktop) { throw 'Docker Desktop application not found. Install Docker Desktop; a Docker CLI alone is insufficient.' }
            # Launch Docker Desktop so its Linux engine can become available.
            Start-Process -FilePath $desktop -WindowStyle Hidden
            Write-Host 'Complete Docker Desktop first-run prompts and select the WSL 2 Linux backend.'
            $ready = $false
            # Retry Docker readiness for at most five minutes.
            for ($i=0; $i -lt 60; $i++) {
                # Read the Docker engine status and retain diagnostics for startup retries.
                $engine = Probe 'docker' @('info','--format','{{.OSType}}')
                if ($engine.Output -match '(?i)manually paused') { throw 'Docker Desktop is paused. Open its tray menu or Dashboard, resume Docker Desktop, then rerun setup.bat.' }
                if (TestEngineReady $engine) { $ready=$true; break }
                if ($i % 6 -eq 0) { Write-Host "Waiting for Docker Linux engine ($($i * 5)/300 seconds)... Last response: $($engine.Output)" }
                # Allow Docker startup time before the next readiness probe.
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
        # Verify that the Docker Compose plugin is installed.
        Run 'docker' @('compose','version')
    }
    Task 'Set environment and persistent directories' {
        # Create each persistent bind-mount directory while preserving its data.
        foreach ($dir in @('home','jenkins','workspace')) { New-Item -ItemType Directory -Force -Path (Join-Path $data $dir) | Out-Null }
        # Persist the user setting for future terminal sessions.
        [Environment]::SetEnvironmentVariable('DEVOPS_DATA_DIR',$data,'User')
        # Expose the selected storage directory to Docker Compose in this process.
        $env:DEVOPS_DATA_DIR = $data.Replace('\','/')
        # User PATH is preserved in full; avoid setx truncation.
        $userPath = [Environment]::GetEnvironmentVariable('Path','User')
        $dockerBin = "$env:ProgramFiles\Docker\Docker\resources\bin"
        if (($userPath -split ';') -notcontains $dockerBin) { [Environment]::SetEnvironmentVariable('Path',(([string]$userPath).TrimEnd(';')+';'+$dockerBin),'User') }
        # Record the selected data location as JSON for later Compose sessions.
        $saved = @{DataDirectory=$data} | ConvertTo-Json
        # Write the generated configuration or manifest to the selected path.
        Set-Content -LiteralPath (Join-Path $root 'setup-state.json') -Value $saved
    }
    Task 'Build and start Ubuntu DevOps container' {
        # Build the Ubuntu tool image and display detailed build progress.
        Run 'docker' @('compose','--progress','plain','-f',(Join-Path $root 'compose.yaml'),'build')
        # Start services and wait for their configured health checks.
        Run 'docker' @('compose','-f',(Join-Path $root 'compose.yaml'),'up','-d','--wait','--wait-timeout','300')
        # Run all installed-tool version checks inside Ubuntu.
        Run 'docker' @('exec','devops-ubuntu','bash','/usr/local/bin/verify-tools')
    }
    Task 'Start Kubernetes and install Argo CD' {
        # Start or reuse the Docker-backed local Kubernetes cluster.
        Run 'minikube' @('start','-p','devops-laptop','--driver=docker','--cpus=2','--memory=4096')
        # Run the Kubernetes helper within the main transcript and exception handler.
        & (Join-Path $root 'setup-kubernetes.ps1')
    }
    Task 'Generate GitHub SSH key and local TLS certificate' {
        # Generate or preserve SSH/TLS keys as the persistent Ubuntu user.
        Run 'docker' @('exec','-u','devops','devops-ubuntu','bash','/usr/local/bin/create-keys')
        # Export only the public GitHub SSH key to the Windows setup folder.
        Run 'docker' @('cp','devops-ubuntu:/home/devops/.ssh/github_devops.pub',(Join-Path $root 'github_devops.pub'))
    }
    Task 'Write access guide on Ubuntu Desktop and Windows' {
        # Place the access guide in the conventional Ubuntu Desktop directory.
        Run 'docker' @('cp',(Join-Path $root 'ACCESS.md'),'devops-ubuntu:/home/devops/Desktop/DEVOPS-ACCESS.md')
        # Assign the Ubuntu access guide to the devops user in the named container.
        Run 'docker' @('exec','devops-ubuntu','chown','devops:devops','/home/devops/Desktop/DEVOPS-ACCESS.md')
        # Copy the report or completed log to its required Windows destination.
        Copy-Item -LiteralPath (Join-Path $root 'ACCESS.md') -Destination (Join-Path $root 'DEVOPS-ACCESS.md') -Force
    }
    Write-Host "`nSUCCESS: See DEVOPS-ACCESS.md for login and GitHub registration steps." -ForegroundColor Green
} catch {
    Write-Host "`n[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Fix the reported task and rerun. Existing data and keys are preserved.'
    exit 1
} finally {
    if ($transcribing) {
        # Close the transcript before copying the completed log.
        Stop-Transcript | Out-Null
        if ($data -and $data -ne $root) { Copy-Item -LiteralPath (Join-Path $root 'log.txt') -Destination (Join-Path $data 'log.txt') -Force }
    }
}
