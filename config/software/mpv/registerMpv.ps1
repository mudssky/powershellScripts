#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Registers mpv as a system-wide file handler and associates file extensions.

.DESCRIPTION
    This script creates the necessary registry keys to register mpv (installed via Scoop)
    as a media player in Windows. It associates common video and audio extensions.

.PARAMETER Check
    If specified, checks if mpv is already correctly registered without making changes.

.PARAMETER Force
    If specified, forces re-registration even if already registered.

.EXAMPLE
    .\registerMpv.ps1
    Registers mpv and associates files.

.EXAMPLE
    .\registerMpv.ps1 -Check
    Verifies if mpv is already registered.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Check,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ================= Configuration =================

# 1. Get Scoop mpv path
try {
    $MpvDir = scoop prefix mpv
}
catch {
    Write-Error "Scoop or mpv not found. Please ensure they are installed."
    if ($Host.UI.RawUI -and !$Check) { Read-Host "Press Enter to exit..." }
    exit 1
}

$MpvExe = Join-Path $MpvDir "mpv.exe"
$IconFile = "$MpvExe,0"
$ProgId = "io.mpv.player"
$AppName = "mpv Media Player"

# Common video and audio formats
$Extensions = @(
    ".mkv", ".mp4", ".avi", ".mov", ".webm", ".flv", ".vob", ".ogv", ".ogg",
    ".mp3", ".flac", ".wav", ".m4a", ".aac", ".wmv", ".rmvb", ".ts", ".m2ts"
)

# ================= Registration Check Logic =================

function Test-MpvRegistered {
    $isRegistered = $true

    # 1. Check ProgID
    $progIdPath = "HKCU:\Software\Classes\$ProgId"
    if (!(Test-Path $progIdPath)) { return $false }

    # 1.1 Check DefaultIcon
    $iconPath = Join-Path $progIdPath "DefaultIcon"
    if (!(Test-Path $iconPath)) { return $false }
    $iconValue = Get-ItemPropertyValue -Path $iconPath -Name "(default)" -ErrorAction SilentlyContinue
    if ($iconValue -ne $IconFile) { return $false }

    # 2. Check Command
    $cmdPath = Join-Path $progIdPath "shell\open\command"
    if (!(Test-Path $cmdPath)) { return $false }
    $cmdValue = Get-ItemPropertyValue -Path $cmdPath -Name "(default)" -ErrorAction SilentlyContinue
    if ($cmdValue -ne "`"$MpvExe`" `"%1`"") { return $false }

    # 3. Check RegisteredApplications
    $regAppPath = "HKCU:\Software\RegisteredApplications"
    $regValue = Get-ItemPropertyValue -Path $regAppPath -Name "mpv" -ErrorAction SilentlyContinue
    if ($regValue -ne "Software\Clients\Media\mpv\Capabilities") { return $false }

    # 4. Check Capabilities
    $capPath = "HKCU:\Software\Clients\Media\mpv\Capabilities\FileAssociations"
    if (!(Test-Path $capPath)) { return $false }

    return $isRegistered
}

if ($Check) {
    $registered = Test-MpvRegistered
    Write-Output $registered
    if ($registered) { exit 0 } else { exit 1 }
}

# ================= Admin Privilege Check =================

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    if ($PSBoundParameters.ContainsKey('Force') -or !(Test-MpvRegistered)) {
        Write-Host "Requesting Administrator privileges for registry changes..." -ForegroundColor Yellow
        Start-Process pwsh.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait
        exit
    }
}

# Skip if already registered and not forced
if (!(Test-MpvRegistered) -or $Force) {
    Write-Host "Registering mpv..." -ForegroundColor Cyan
}
else {
    Write-Host "mpv is already registered. Use -Force to re-register." -ForegroundColor Green
    exit 0
}

# ================= Registry Writing =================

Write-Host "Writing registry information..." -ForegroundColor Cyan

try {
    # 1. Create ProgID
    $RegPath = "HKCU:\Software\Classes\$ProgId"
    if ($PSCmdlet.ShouldProcess($RegPath, "Create/Update Registry Key")) {
        New-Item -Path $RegPath -Force | Out-Null
        Set-ItemProperty -Path $RegPath -Name "(default)" -Value $AppName
        Set-ItemProperty -Path $RegPath -Name "FriendlyTypeName" -Value "Video File"

        # Default Icon
        New-Item -Path "$RegPath\DefaultIcon" -Force | Out-Null
        Set-ItemProperty -Path "$RegPath\DefaultIcon" -Name "(default)" -Value $IconFile

        # Open Command
        New-Item -Path "$RegPath\shell\open\command" -Force | Out-Null
        Set-ItemProperty -Path "$RegPath\shell\open\command" -Name "(default)" -Value "`"$MpvExe`" `"%1`""

        # 2. Register Capabilities
        $CapPath = "HKCU:\Software\Clients\Media\mpv\Capabilities"
        New-Item -Path "$CapPath\FileAssociations" -Force | Out-Null
        Set-ItemProperty -Path $CapPath -Name "ApplicationName" -Value $AppName
        Set-ItemProperty -Path $CapPath -Name "ApplicationDescription" -Value "mpv media player"

        # 3. Associate Extensions
        foreach ($ext in $Extensions) {
            Set-ItemProperty -Path "$CapPath\FileAssociations" -Name $ext -Value $ProgId
        }

        # 4. Registered Applications
        $RegAppPath = "HKCU:\Software\RegisteredApplications"
        if (!(Test-Path $RegAppPath)) {
            New-Item -Path $RegAppPath -Force | Out-Null
        }
        Set-ItemProperty -Path $RegAppPath -Name "mpv" -Value "Software\Clients\Media\mpv\Capabilities"
    }

    Write-Host "------------------------------------------------" -ForegroundColor Green
    Write-Host "Registration Complete!" -ForegroundColor Green
    Write-Host "Please perform the final step: Set default apps manually." -ForegroundColor Yellow
    Write-Host "1. Open Windows Settings -> Apps -> Default Apps"
    Write-Host "2. Search for 'mpv'"
    Write-Host "3. Set it as default"
    Write-Host "------------------------------------------------"

    # Refresh explorer icons
    $code = @'
    [System.Runtime.InteropServices.DllImport("Shell32.dll")] 
    private static extern int SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);
    public static void Refresh() { SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero); }
'@
    Add-Type -MemberDefinition $code -Namespace Win32 -Name ShellUtils -ErrorAction SilentlyContinue
    [Win32.ShellUtils]::Refresh()
}
catch {
    Write-Error "Failed to write registry: $_"
    exit 1
}

if ($Host.UI.RawUI -and !$Check) {
    Read-Host "Press Enter to finish..."
}