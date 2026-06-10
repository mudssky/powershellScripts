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

.PARAMETER InstallPlugins
    If specified, installs recommended plugins (uosc and thumbfast) via tools/install/install_plugins.ps1.

.PARAMETER InstallShaders
    If specified, downloads and installs shaders via tools/install/download_shaders.ps1.

.PARAMETER Full
    If specified, performs a full installation: MPV, Plugins, Shaders, and Registration.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Check,
    [switch]$InstallPlugins,
    [switch]$InstallShaders,
    [switch]$Full
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MpvLocalConfigContent {
    <#
    .SYNOPSIS
        生成当前平台的 mpv 本地覆盖配置。

    .DESCRIPTION
        返回只适合写入 mpv_local.conf 的平台专用配置，避免通用 mpv.conf
        在 macOS/Linux 上加载 Windows 专用后端选项。

    .OUTPUTS
        System.String 当前平台的 mpv 本地配置文本。
    #>
    [CmdletBinding()]
    param()

    if ($IsWindows) {
        return @'
# Windows 平台默认覆盖
# 使用 d3d11 和 wasapi，避免跨平台 mpv.conf 在非 Windows 上解析失败。
gpu-api=d3d11
d3d11-output-format=auto
ao=wasapi
'@
    }

    if ($IsMacOS) {
        return @'
# macOS 平台默认覆盖
# Homebrew mpv 由 mpv 自动选择可用图形后端；这里只固定原生音频输出。
ao=coreaudio
'@
    }

    if ($IsLinux) {
        return @'
# Linux 平台默认覆盖
# 不强制指定图形和音频后端，由 mpv 按桌面环境自动选择。
'@
    }

    return @'
# 未识别平台默认覆盖
# 不强制指定图形和音频后端，由 mpv 自动选择。
'@
}

function Initialize-MpvLocalConfig {
    <#
    .SYNOPSIS
        初始化 mpv_local.conf 本地覆盖文件。

    .DESCRIPTION
        当本地覆盖文件不存在或内容为空时写入当前平台默认配置；如果用户已经
        写入本机设置，则只提示并保留原内容，避免安装脚本覆盖用户偏好。

    .PARAMETER Path
        mpv_local.conf 的绝对路径。

    .OUTPUTS
        None.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $shouldWriteDefault = $true
    if (Test-Path $Path) {
        $existingContent = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $shouldWriteDefault = [string]::IsNullOrWhiteSpace($existingContent)
    }

    if (-not $shouldWriteDefault) {
        Write-Host "Keeping existing mpv_local.conf; platform defaults were not overwritten." -ForegroundColor Gray
        return
    }

    $defaultContent = Get-MpvLocalConfigContent
    if ($PSCmdlet.ShouldProcess($Path, "Write platform default mpv local config")) {
        Write-Host "Writing platform defaults to mpv_local.conf..."
        Set-Content -LiteralPath $Path -Value $defaultContent -Encoding utf8
    }
}

function New-MpvMacApplicationWrapper {
    <#
    .SYNOPSIS
        创建 macOS Finder 可识别的 mpv.app 外壳。

    .DESCRIPTION
        Homebrew 安装的 mpv 是命令行程序，不会出现在“应用程序”中。本函数
        生成一个 AppleScript 应用外壳，把 Finder 传入的视频文件路径转发给
        Homebrew mpv，从而支持“打开方式”和双击关联。

    .PARAMETER MpvPath
        Homebrew mpv 命令的绝对路径。

    .PARAMETER AppPath
        要创建的 mpv.app 目标路径。

    .OUTPUTS
        None.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MpvPath,

        [Parameter(Mandatory = $true)]
        [string]$AppPath
    )

    if (-not $IsMacOS) {
        return
    }

    if (-not (Get-Command osacompile -ErrorAction SilentlyContinue)) {
        Write-Warning "osacompile not found; skipped creating mpv.app wrapper."
        return
    }

    if (-not (Test-Path $MpvPath)) {
        Write-Warning "mpv executable not found at $MpvPath; skipped creating mpv.app wrapper."
        return
    }

    $appParent = Split-Path -Parent $AppPath
    if (-not (Test-Path $appParent)) {
        New-Item -ItemType Directory -Path $appParent -Force | Out-Null
    }

    $escapedMpvPath = $MpvPath.Replace('\', '\\').Replace('"', '\"')
    $scriptContent = @"
property mpvPath : "$escapedMpvPath"

on open mediaFiles
    set commandParts to {}
    repeat with mediaFile in mediaFiles
        set end of commandParts to quoted form of POSIX path of mediaFile
    end repeat

    set AppleScript's text item delimiters to " "
    set mediaArgs to commandParts as text
    set AppleScript's text item delimiters to ""

    do shell script quoted form of mpvPath & " -- " & mediaArgs & " >/dev/null 2>&1 &"
end open

on run
    do shell script quoted form of mpvPath & " --player-operation-mode=pseudo-gui >/dev/null 2>&1 &"
end run
"@

    $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "mpv-wrapper-$([System.Guid]::NewGuid()).applescript"
    try {
        Set-Content -LiteralPath $tempScript -Value $scriptContent -Encoding utf8

        if (Test-Path $AppPath) {
            Remove-Item -LiteralPath $AppPath -Recurse -Force
        }

        if ($PSCmdlet.ShouldProcess($AppPath, "Create macOS mpv.app wrapper")) {
            & osacompile -o $AppPath $tempScript
            if ($LASTEXITCODE -ne 0) {
                throw "osacompile failed with exit code $LASTEXITCODE"
            }

            $plistPath = Join-Path $AppPath "Contents/Info.plist"
            # 让 LaunchServices 把这个外壳识别为媒体文件查看器，便于 Finder 选择“打开方式”。
            & /usr/libexec/PlistBuddy -c "Set :CFBundleName mpv" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string mpv" $plistPath 2>$null
            & /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName mpv" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string io.mpv.homebrew.wrapper" $plistPath 2>$null
            & /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.mpv.homebrew.wrapper" $plistPath
            & /usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" $plistPath 2>$null
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes array" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0 dict" $plistPath 2>$null
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Media Files" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.movie" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string public.audio" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:2 string public.audiovisual-content" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:3 string public.mpeg-4" $plistPath
            & /usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:4 string org.matroska.mkv" $plistPath

            Write-Host "Created Finder app wrapper: $AppPath" -ForegroundColor Green
        }
    }
    finally {
        if (Test-Path $tempScript) {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
}

# Get the script's root directory (source of configuration)
$sourcePath = $PSScriptRoot
if (-not $sourcePath) {
    $sourcePath = Get-Location
}
# Resolve to absolute path to ensure consistency
$sourcePath = (Resolve-Path $sourcePath).Path
$toolsDir = Join-Path $sourcePath "tools/install"

# -----------------------------------------------------------------------------
# Configuration Initialization
# -----------------------------------------------------------------------------
# Ensure mpv_local.conf exists and carries safe platform defaults
$localConfPath = Join-Path $sourcePath "mpv_local.conf"
if (-not $Check) {
    Initialize-MpvLocalConfig -Path $localConfPath
}

if ($Full) {
    Write-Host "Full installation mode selected." -ForegroundColor Cyan
    $InstallPlugins = $true
    $InstallShaders = $true
}

$doExtras = $InstallPlugins -or $InstallShaders
$doCore = (-not $doExtras) -or $Full
$doRegister = $IsWindows -and $doCore

if (-not $Check) {
    Write-Host "Source Config Path: $sourcePath"
}

# -----------------------------------------------------------------------------
# Core Installation (mpv + link)
# -----------------------------------------------------------------------------
if ($doCore -and -not $Check) {
    if ($IsWindows) {
        Write-Host "Detected OS: Windows"

        # Check if scoop is installed
        if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Error "Scoop is not installed. Please install Scoop first (https://scoop.sh)."
            exit 1
        }

        Write-Host "Checking if mpv is already installed..."
        $mpvPrefix = scoop prefix mpv 2>$null
        if ($null -eq $mpvPrefix -or !(Test-Path $mpvPrefix)) {
            Write-Host "mpv not found. Installing via scoop..."
            scoop install mpv
        }
        else {
            Write-Host "mpv is already installed at: $mpvPrefix"
        }

        # Locate mpv installation again to be sure (or use the one we found)
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
                
                # Ensure mpv is not running
                Get-Process mpv -ErrorAction SilentlyContinue | Stop-Process -Force

                # Remove ReadOnly attribute if present
                if ($item.Attributes.HasFlag([System.IO.FileAttributes]::ReadOnly)) {
                    $item.Attributes = $item.Attributes -band -not [System.IO.FileAttributes]::ReadOnly
                }

                # Use cmd /c rmdir which is more reliable for removing junctions than Remove-Item
                cmd /c "rmdir `"$targetPath`""
                
                if (Test-Path $targetPath) {
                    # Fallback to .NET method
                    try { [System.IO.Directory]::Delete($targetPath) } catch {}
                }

                if (Test-Path $targetPath) {
                    Remove-Item $targetPath -Force
                }
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

        $mpvCommand = Get-Command mpv -ErrorAction SilentlyContinue
        if ($mpvCommand) {
            $macAppPath = Join-Path $HOME "Applications/mpv.app"
            New-MpvMacApplicationWrapper -MpvPath $mpvCommand.Source -AppPath $macAppPath
        }
        else {
            Write-Warning "mpv command not found after Homebrew installation; skipped creating mpv.app wrapper."
        }

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
}

# -----------------------------------------------------------------------------
# Plugin Installation (uosc, thumbfast)
# -----------------------------------------------------------------------------
if ($InstallPlugins) {
    $pluginScript = Join-Path $toolsDir "install_plugins.ps1"
    if (Test-Path $pluginScript) {
        & $pluginScript -MpvConfigRoot $sourcePath
    }
    else {
        Write-Warning "Plugin installation script not found at $pluginScript"
    }
}

# -----------------------------------------------------------------------------
# Shader Installation
# -----------------------------------------------------------------------------
if ($InstallShaders) {
    $shaderScript = Join-Path $toolsDir "download_shaders.ps1"
    if (Test-Path $shaderScript) {
        & $shaderScript -MpvConfigRoot $sourcePath
    }
    else {
        Write-Warning "Shader download script not found at $shaderScript"
    }
}

# -----------------------------------------------------------------------------
# Register mpv as a system-wide handler (Windows only)
# -----------------------------------------------------------------------------
if ($doRegister -and -not $Check) {
    $registerScript = Join-Path $toolsDir "registerMpv.ps1"
    if (Test-Path $registerScript) {
        Write-Host "Registering mpv as system-wide handler..."
        & $registerScript
    }
    else {
        Write-Warning "Registration script not found at $registerScript"
    }
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
                                $registerScript = Join-Path $toolsDir "registerMpv.ps1"
                                if (Test-Path $registerScript) {
                                    $isRegistered = & $registerScript -Check
                                    if ($isRegistered -eq $true) {
                                        $isInstalled = $true
                                    }
                                }
                                else {
                                    # If register script is missing but link is OK, we consider it partially installed
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

        if ($isInstalled -and $IsMacOS) {
            $macAppPath = Join-Path $HOME "Applications/mpv.app"
            if (-not (Test-Path $macAppPath)) {
                $isInstalled = $false
            }
        }
    }

    Write-Output $isInstalled
    if ($isInstalled) { exit 0 } else { exit 1 }
}

if (-not $Check -and -not $Full) {
    Write-Host "`n[Tip] You can install extras by running:" -ForegroundColor Yellow
    Write-Host "      .\install.ps1 -InstallPlugins" -ForegroundColor Yellow
    Write-Host "      .\install.ps1 -InstallShaders" -ForegroundColor Yellow
    Write-Host "      .\install.ps1 -Full" -ForegroundColor Yellow
}
