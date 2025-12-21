#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

# Get the script's root directory (source of configuration)
$sourcePath = $PSScriptRoot
if (-not $sourcePath) {
    $sourcePath = Get-Location
}
Write-Host "Source Config Path: $sourcePath"

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
