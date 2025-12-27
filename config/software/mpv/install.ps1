#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Installs and configures mpv with portable_config and system-wide registration.

.DESCRIPTION
    This script automates the installation of mpv (via Scoop on Windows or Homebrew on macOS/Linux),
    links the local configuration to the mpv config directory, and on Windows, 
    registers mpv as a system-wide file handler.

.PARAMETER Check
    If specified, checks if the configuration is correctly installed and linked.

.EXAMPLE
    .\install.ps1
    Installs mpv and links configuration.

.EXAMPLE
    .\install.ps1 -Check
    Verifies the installation status.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get the script's root directory (source of configuration)
$sourcePath = $PSScriptRoot
if (-not $sourcePath) {
    $sourcePath = Get-Location
}
# Resolve to absolute path to ensure consistency
$sourcePath = (Resolve-Path $sourcePath).Path

if (-not $Check) {
    Write-Host "Source Config Path: $sourcePath"
}

# -----------------------------------------------------------------------------
# Check Mode Implementation
# -----------------------------------------------------------------------------
if ($Check) {
    $isInstalled = $false

    if ($IsWindows) {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            try {
                $mpvPath = scoop prefix mpv 2>$null
                if ($mpvPath -and (Test-Path $mpvPath)) {
                    $targetPath = Join-Path $mpvPath "portable_config"
                    if (Test-Path $targetPath) {
                        $item = Get-Item $targetPath
                        # Check if it is a reparse point (symlink/junction)
                        if ($item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
                            # Verify target
                            $target = $item.Target
                            # Resolve target to absolute path if possible, or compare strings
                            if ($target -and ((Resolve-Path $target).Path -eq $sourcePath)) {
                                # Also check if registered
                                $registerScript = Join-Path $sourcePath "registerMpv.ps1"
                                if (Test-Path $registerScript) {
                                    $isRegistered = & $registerScript -Check
                                    if ($isRegistered -eq $true) {
                                        $isInstalled = $true
                                    }
                                }
                                else {
                                    # If register script is missing but link is OK, we consider it partially installed
                                    # But for the sake of this task, let's say it's OK if link is OK
                                    $isInstalled = $true
                                }
                            }
                        }
                    }
                }
            }
            catch {}
        }
    }
    elseif ($IsMacOS -or $IsLinux) {
        $configDir = Join-Path $HOME ".config"
        $targetPath = Join-Path $configDir "mpv"
        
        if (Test-Path $targetPath) {
            $item = Get-Item $targetPath
            if ($item.LinkType) {
                $target = $item.Target
                # Resolve potential relative paths in symlinks
                # But simple string comparison is a good first step
                if ($target -eq $sourcePath) {
                    $isInstalled = $true
                }
                else {
                    # Try resolving
                    try {
                        # Join path if relative? 
                        # PowerShell's .Target on Unix usually gives the raw link content
                        # If it's absolute, Resolve-Path works.
                        if (Test-Path $target) {
                            if ((Resolve-Path $target).Path -eq $sourcePath) {
                                $isInstalled = $true
                            }
                        }
                    }
                    catch {}
                }
            }
        }
    }

    Write-Output $isInstalled
    if ($isInstalled) { exit 0 } else { exit 1 }
}

# -----------------------------------------------------------------------------
# Windows Implementation (Scoop)
# -----------------------------------------------------------------------------
if ($IsWindows) {
    Write-Host "Detected OS: Windows"

    # Check if scoop is installed
    if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Error "Scoop is not installed. Please install Scoop first (https://scoop.sh)."
        exit 1
    }

    Write-Host "Installing/Updating mpv via scoop..."
    scoop install mpv

    # Locate mpv installation
    try {
        $mpvPath = scoop prefix mpv
    }
    catch {
        Write-Error "Failed to determine mpv path using 'scoop prefix mpv'."
        exit 1
    }

    if (!(Test-Path $mpvPath)) {
        Write-Error "Could not find mpv installation at $mpvPath"
        exit 1
    }

    # Define target path for portable_config
    $targetPath = Join-Path $mpvPath "portable_config"
    Write-Host "Target Path: $targetPath"

    # Handle existing target
    if (Test-Path $targetPath) {
        $item = Get-Item $targetPath
        # Check if it is a reparse point (symlink/junction)
        if ($item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
            Write-Host "Removing existing link..."
            Remove-Item $targetPath -Force
        }
        else {
            Write-Warning "Directory '$targetPath' already exists and is not a link."
            $confirm = Read-Host "Do you want to delete it and replace with symlink? (y/n)"
            if ($confirm -eq 'y') {
                Remove-Item $targetPath -Recurse -Force
            }
            else {
                Write-Error "Aborted."
                exit 1
            }
        }
    }

    # Create Junction
    Write-Host "Creating Junction..."
    New-Item -ItemType Junction -Path $targetPath -Target $sourcePath | Out-Null
    Write-Host "Success! mpv is now using this portable_config."

    # -----------------------------------------------------------------------------
    # Register mpv as a system-wide handler (Windows only)
    # -----------------------------------------------------------------------------
    $registerScript = Join-Path $sourcePath "registerMpv.ps1"
    if (Test-Path $registerScript) {
        Write-Host "Registering mpv as system-wide handler..."
        & $registerScript
    }
    else {
        Write-Warning "Registration script not found at $registerScript"
    }
}

# -----------------------------------------------------------------------------
# macOS / Linux Implementation (Homebrew)
# -----------------------------------------------------------------------------
elseif ($IsMacOS -or $IsLinux) {
    if ($IsMacOS) { Write-Host "Detected OS: macOS" }
    else { Write-Host "Detected OS: Linux" }

    # Check for Homebrew
    if (!(Get-Command brew -ErrorAction SilentlyContinue)) {
        Write-Error "Homebrew is not installed. Please install Homebrew first."
        exit 1
    }

    Write-Host "Installing/Updating mpv via Homebrew..."
    brew install mpv

    # Define target path (~/.config/mpv)
    $configDir = Join-Path $HOME ".config"
    $targetPath = Join-Path $configDir "mpv"
    Write-Host "Target Path: $targetPath"

    # Handle existing target
    if (Test-Path $targetPath) {
        # Check if it's a symlink
        $isSymlink = (Get-Item $targetPath).LinkType -ne $null
        
        if ($isSymlink) {
            Write-Host "Removing existing symlink..."
            Remove-Item $targetPath -Force
        }
        else {
            Write-Warning "Directory '$targetPath' already exists and is not a symlink."
            $confirm = Read-Host "Do you want to overwrite it with a symlink to this repo? (y/n)"
            if ($confirm -eq 'y') {
                Remove-Item $targetPath -Recurse -Force
            }
            else {
                Write-Error "Aborted."
                exit 1
            }
        }
    }

    # Ensure parent directory exists
    if (!(Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }

    # Create Symlink
    Write-Host "Creating Symlink..."
    New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath | Out-Null
    Write-Host "Success! Linked $sourcePath to $targetPath"
}
else {
    Write-Error "Unsupported Operating System."
    exit 1
}
