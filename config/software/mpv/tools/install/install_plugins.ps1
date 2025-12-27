#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Installs recommended plugins (uosc, thumbfast) for MPV.

.DESCRIPTION
    Downloads and installs the latest versions of uosc and thumbfast.
    
.PARAMETER MpvConfigRoot
    The root directory of the MPV configuration.

.EXAMPLE
    .\install_plugins.ps1 -MpvConfigRoot "C:\path\to\mpv\config"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MpvConfigRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n------------------------------------------------"
Write-Host "Installing Plugins (uosc, thumbfast)..." -ForegroundColor Cyan
Write-Host "------------------------------------------------"

# Ensure directories exist
$scriptsDir = Join-Path $MpvConfigRoot "scripts"
$scriptOptsDir = Join-Path $MpvConfigRoot "script-opts"

if (!(Test-Path $scriptsDir)) { New-Item -ItemType Directory -Path $scriptsDir | Out-Null }
if (!(Test-Path $scriptOptsDir)) { New-Item -ItemType Directory -Path $scriptOptsDir | Out-Null }

# 1. Install uosc
Write-Host "Downloading and installing uosc..."
$uoscUrl = "https://github.com/tomasklaen/uosc/releases/latest/download/uosc.zip"
$uoscZip = Join-Path $MpvConfigRoot "uosc.zip"
try {
    Invoke-WebRequest -Uri $uoscUrl -OutFile $uoscZip -ErrorAction Stop
    # Expand to MpvConfigRoot. uosc.zip typically contains contents ready for root.
    Expand-Archive -Path $uoscZip -DestinationPath $MpvConfigRoot -Force
    Remove-Item $uoscZip -Force
    Write-Host "uosc installed successfully." -ForegroundColor Green
}
catch {
    Write-Warning "Failed to install uosc: $_"
}

# 2. Install thumbfast
Write-Host "Downloading and installing thumbfast..."
$thumbfastBase = "https://raw.githubusercontent.com/po5/thumbfast/master"
try {
    # thumbfast.lua
    $thumbfastLua = Join-Path $scriptsDir "thumbfast.lua"
    Invoke-WebRequest -Uri "$thumbfastBase/thumbfast.lua" -OutFile $thumbfastLua -ErrorAction Stop
    Write-Host "thumbfast.lua installed." -ForegroundColor Green
    
    # thumbfast.conf
    $thumbfastConf = Join-Path $scriptOptsDir "thumbfast.conf"
    if (!(Test-Path $thumbfastConf)) {
        Invoke-WebRequest -Uri "$thumbfastBase/thumbfast.conf" -OutFile $thumbfastConf -ErrorAction Stop
        Write-Host "thumbfast.conf installed." -ForegroundColor Green
    }
    else {
        Write-Host "thumbfast.conf already exists, skipping." -ForegroundColor Gray
    }
}
catch {
    Write-Warning "Failed to install thumbfast: $_"
}

Write-Host "`nPlugins installation complete." -ForegroundColor Cyan
