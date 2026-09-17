# ==============================================================================
# Tomcat Monitoring Platform — Windows Host Bootstrap & OpenSSH Hardening Script
# Architecture Reference: TM-ADR-0028, TN-018, TN-019
# Target OS: Windows Server 2019 / 2022 / 2025
# ==============================================================================
# Usage:
#   Run in PowerShell as Administrator:
#   .\scripts\bootstrap-windows-host.ps1
#   Or with custom base64 key:
#   .\scripts\bootstrap-windows-host.ps1 -Base64PublicKey "<BASE64_PUBLIC_KEY>"
# ==============================================================================

param (
    [string]$Base64PublicKey = "c3NoLXJzYSBBQUFBQjNOemFDMXljMkVBQUFBREFRQUJBQUFCQVFESEpkNzQyMS9PdUxONVhoV2crMDZqODUvODFQT3J3QURxUTV6TTV2dWRBK20wdFpQTkQ3NlpVL2ZLeThtcVV5Yk96c3NNNmk0ZCtaVldRR2NRVno5enpTZU1QU002VGV4UjJrZUVzMmtiSHA2T2MwM3lmWloybUt1bUUxRldDdjNETEx0ckxVdk1IVDVxNVhROHVKTXNManlNY2hEY1pHZk1hbXk4dlFYcVgwQ0NzWjZ4WDhyekJUQWxNdW9UcWdDTkplOUVLVUNKcFFMcms2ZXpuTjAvVmYvbXYxSGRKR2hZS2daQ3o5RnhVaW1HZUZBUVlwSTNFVlBmeWl3RUtqaiswYlhIRDRkTTlxbmZjdC9ydzFLb3oxaDVHRmZ0a1FVUVlJYW1iOC8yd3J4UVVNVzhHVzdoUjR3S3hBdmd5clN4Y2pEUDRqT3lRVk9Leld0ZnNnWDc="
)

Write-Host "=== Starting Windows Host OpenSSH Bootstrap & Hardening ===" -ForegroundColor Cyan

# 1. Install OpenSSH Server Feature
Write-Host "[1/7] Ensuring OpenSSH Server capability is installed..."
$capability = Get-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction SilentlyContinue
if ($capability -and $capability.State -ne "Installed") {
    Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" | Out-Null
    Write-Host "      Installed OpenSSH.Server successfully." -ForegroundColor Green
} else {
    Write-Host "      OpenSSH.Server capability already present." -ForegroundColor Green
}

# 2. Configure Service Account to LocalSystem & ssh-agent dependency
Write-Host "[2/7] Configuring service account binding to LocalSystem..."
sc.exe config sshd obj= "LocalSystem" | Out-Null
sc.exe config sshd depend= ssh-agent | Out-Null
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent -ErrorAction SilentlyContinue
Write-Host "      Service account and ssh-agent configured." -ForegroundColor Green

# 3. Set Default Shell to PowerShell (Bebas Line-Wrap via reg.exe)
Write-Host "[3/7] Setting OpenSSH default shell to PowerShell..."
$psPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
reg add HKLM\SOFTWARE\OpenSSH /v DefaultShell /d $psPath /f | Out-Null
Write-Host "      DefaultShell set to PowerShell." -ForegroundColor Green

# 4. Generate Host Keys & Apply Strict ACL (.NET SYSTEM & Administrators Only)
Write-Host "[4/7] Generating host keys and securing ACL permissions..."
& "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -A 2>$null

$systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
$adminsSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")

Get-Item "C:\ProgramData\ssh\ssh_host_*_key" -ErrorAction SilentlyContinue | ForEach-Object {
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", "None", "None", "Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminsSid, "FullControl", "None", "None", "Allow")))
    $acl.SetOwner($systemSid)
    Set-Acl -Path $_.FullName -AclObject $acl
}
Write-Host "      Host keys ACL hardened (SYSTEM & Administrators only)." -ForegroundColor Green

# 5. Write Clean sshd_config with StrictModes no & SFTP Subsystem
Write-Host "[5/7] Writing clean sshd_config (StrictModes no, SFTP enabled)..."
Set-Content "C:\ProgramData\ssh\sshd_config" @(
    "Port 22",
    "PubkeyAuthentication yes",
    "PasswordAuthentication yes",
    "StrictModes no",
    "Subsystem sftp sftp-server.exe"
) -Encoding ASCII
Write-Host "      sshd_config written successfully." -ForegroundColor Green

# 6. Inject Authorized Keys
Write-Host "[6/7] Injecting public keys via clean Base64 decoding..."
if ($Base64PublicKey) {
    $bytes = [Convert]::FromBase64String($Base64PublicKey)
    if (-not (Test-Path "$env:USERPROFILE\.ssh")) {
        New-Item -Path "$env:USERPROFILE\.ssh" -ItemType Directory | Out-Null
    }
    [System.IO.File]::WriteAllBytes("$env:USERPROFILE\.ssh\authorized_keys", $bytes)
    [System.IO.File]::WriteAllBytes("C:\ProgramData\ssh\administrators_authorized_keys", $bytes)
    Write-Host "      Public keys injected to profile and administrators_authorized_keys." -ForegroundColor Green
}

# 7. Enable Firewall Port 22 and Start sshd
Write-Host "[7/7] Enabling firewall rule and restarting sshd service..."
Get-NetFirewallRule -DisplayName "*OpenSSH*" -ErrorAction SilentlyContinue | Enable-NetFirewallRule -ErrorAction SilentlyContinue
Set-Service sshd -StartupType Automatic
Restart-Service sshd
Start-Sleep -Seconds 2

$status = (Get-Service sshd).Status
Write-Host "=== OpenSSH Server Bootstrap Completed: Status = $status ===" -ForegroundColor Green
