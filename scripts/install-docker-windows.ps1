# ==============================================================================
# Tomcat Monitoring Platform — Windows Docker Engine (Windows Containers) Installer
# Architecture Reference: TM-ADR-0026, TN-018, TN-019
# Target OS: Windows Server 2019 / 2022 / 2025
# ==============================================================================
# Usage:
#   Run in PowerShell as Administrator:
#   .\scripts\install-docker-windows.ps1
# ==============================================================================

param (
    [string]$DockerVersion = "26.1.4"
)

Write-Host "=== Starting Docker Engine Installation for Windows Containers ===" -ForegroundColor Cyan

# 1. Check and Install Windows Feature 'Containers'
Write-Host "[1/5] Checking Windows Feature: Containers..."
$feature = Get-WindowsFeature -Name Containers
if (-not $feature.Installed) {
    Write-Host "      Installing Windows Feature: Containers..." -ForegroundColor Yellow
    $res = Install-WindowsFeature -Name Containers
    if ($res.RestartNeeded -eq "Yes") {
        Write-Warning "System requires a reboot to initialize the 'windowsfilter' container storage driver."
        Write-Warning "Please reboot the server (Restart-Computer -Force) and re-run this script after reboot."
        exit 3010
    }
} else {
    Write-Host "      Windows Feature: Containers is already installed." -ForegroundColor Green
}

# 2. Download Official Docker Static Binaries (Windows x86_64)
$downloadUrl = "https://download.docker.com/win/static/stable/x86_64/docker-$DockerVersion.zip"
$zipPath = "$env:TEMP\docker-$DockerVersion.zip"
$targetDir = "C:\Program Files\docker"

Write-Host "[2/5] Downloading Docker Engine v$DockerVersion static binaries..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $zipPath

Write-Host "[3/5] Extracting Docker binaries to $targetDir..."
if (-not (Test-Path "C:\Program Files")) { New-Item -Path "C:\Program Files" -ItemType Directory | Out-Null }
Expand-Archive -Path $zipPath -DestinationPath "C:\Program Files" -Force
Remove-Item -Path $zipPath -Force

# 3. Add Docker to Machine PATH if not present
Write-Host "[4/5] Configuring System PATH..."
$machinePath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
if ($machinePath -notlike "*$targetDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$machinePath;$targetDir", [EnvironmentVariableTarget]::Machine)
    $env:Path += ";$targetDir"
}

# 4. Register Docker Daemon Service & Start
Write-Host "[5/5] Registering and starting Docker daemon service..."
if (-not (Get-Service -Name docker -ErrorAction SilentlyContinue)) {
    & "$targetDir\dockerd.exe" --register-service
}

Set-Service -Name docker -StartupType Automatic
Restart-Service docker -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# 5. Verify Installation
$dockerService = Get-Service -Name docker -ErrorAction SilentlyContinue
if ($dockerService -and $dockerService.Status -eq "Running") {
    Write-Host "=== Docker Windows Engine Installed Successfully! ===" -ForegroundColor Green
    & "$targetDir\docker.exe" version
} else {
    Write-Error "Docker service failed to start. Check Windows Event Viewer or run dockerd manually."
}
