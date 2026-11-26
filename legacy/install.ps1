# =====================================================================
#  SyHost - one-line installer
#  Paste into PowerShell and press Enter:
#     irm https://raw.githubusercontent.com/sykait/SyHost/main/legacy/install.ps1 | iex
#  Run the same command again to update (your settings and servers are kept).
# =====================================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repo   = 'sykait/SyHost'
$Branch = 'main'
$Dest   = Join-Path $env:LOCALAPPDATA 'Programs\SyHost'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host ''
Write-Host '  Downloading SyHost...' -ForegroundColor Red
$tmp = Join-Path $env:TEMP ('syhost-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'syhost.zip'
    Invoke-WebRequest "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $tmp -Force
    $unzipped = Get-ChildItem $tmp -Directory | Select-Object -First 1
    # PowerShell surumu repoda legacy klasorunde durur; yalnizca o kurulur
    $src = Join-Path $unzipped.FullName 'legacy'
    New-Item -ItemType Directory -Force $Dest | Out-Null
    Copy-Item (Join-Path $src '*') $Dest -Recurse -Force
    Get-ChildItem $Dest -Recurse -File | Unblock-File
    Write-Host "  Downloaded to: $Dest" -ForegroundColor Green
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dest 'src\Setup.ps1')