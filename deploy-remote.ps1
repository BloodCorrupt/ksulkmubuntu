<#
.SYNOPSIS
    Deploy KernelSU-Next Builder Suite to remote Ubuntu host over SSH / SCP.

.DESCRIPTION
    Transfers the ksu-x64-builder suite to the remote machine (e.g. bloodtek-jr)
    and optionally executes the automated build pipeline over SSH.

.EXAMPLE
    .\deploy-remote.ps1
    .\deploy-remote.ps1 -RemoteHost "10.13.37.183" -RemoteUser "bloodtek" -ExecuteNow
#>

[CmdletBinding()]
param(
    [string]$RemoteHost = "10.13.37.183",
    [string]$RemoteUser = "bloodtek",
    [int]$RemotePort = 22,
    [string]$RemotePath = "~/ksu-x64-builder",
    [switch]$ExecuteNow
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "  KernelSU-Next Builder Suite - Remote Deployment" -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan

Write-Host "[*] Target Host: $($RemoteUser)@$($RemoteHost):$($RemotePort)" -ForegroundColor Yellow
Write-Host "[*] Remote Path: $($RemotePath)`n" -ForegroundColor Yellow

# Test SSH connectivity
Write-Host "[1/3] Testing SSH connection..." -ForegroundColor Blue
try {
    ssh -p $RemotePort -o BatchMode=yes -o ConnectTimeout=5 "$($RemoteUser)@$($RemoteHost)" "echo 'SSH Connection OK'" 2>$null | Out-Null
    Write-Host "[+] SSH connection test passed!" -ForegroundColor Green
} catch {
    Write-Host "[!] Note: Key-based login not verified, password prompt will appear if necessary." -ForegroundColor DarkYellow
}

# Ensure remote directory exists
Write-Host "`n[2/3] Preparing remote directory: $($RemotePath)..." -ForegroundColor Blue
ssh -p $RemotePort "$($RemoteUser)@$($RemoteHost)" "mkdir -p $($RemotePath)"

# Copy files using scp
Write-Host "`n[3/3] Uploading suite files via SCP..." -ForegroundColor Blue
$currentDir = $PSScriptRoot

# Transfer all script files, configs, and source
scp -P $RemotePort -r `
    "$currentDir\config.env" `
    "$currentDir\ksu-suite.sh" `
    "$currentDir\scripts" `
    "$currentDir\src" `
    "$currentDir\systemd" `
    "$currentDir\README.md" `
    "$($RemoteUser)@$($RemoteHost):$($RemotePath)/"

# Ensure execution permissions on remote
ssh -p $RemotePort "$($RemoteUser)@$($RemoteHost)" "chmod +x $($RemotePath)/ksu-suite.sh $($RemotePath)/scripts/*.sh"

Write-Host "`n[+] Deployment finished successfully!" -ForegroundColor Green
Write-Host "To run the suite on the Ubuntu machine, log in via SSH:" -ForegroundColor Cyan
Write-Host "    ssh $($RemoteUser)@$($RemoteHost)" -ForegroundColor White
Write-Host "    cd $($RemotePath)" -ForegroundColor White
Write-Host "    ./ksu-suite.sh`n" -ForegroundColor White

if ($ExecuteNow) {
    Write-Host "[*] Executing automated pipeline on remote host now..." -ForegroundColor Yellow
    ssh -t -p $RemotePort "$($RemoteUser)@$($RemoteHost)" "cd $($RemotePath) && ./ksu-suite.sh --all"
}
