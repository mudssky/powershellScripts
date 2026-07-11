<#
.SYNOPSIS
    在普通用户上下文安装或验证 Scoop。

.PARAMETER NetworkMode
    Direct、China 或 Auto。

.PARAMETER InstallerPath
    可选本地 Scoop installer 脚本。

.PARAMETER Unattended
    接受根入口交互合同；Scoop 本身不提升。

.PARAMETER NonInteractive
    严格非交互模式。

.OUTPUTS
    文本组件结果；失败退出 1，Blocked 退出 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$NetworkMode = 'Direct',

    [string]$InstallerPath = '',

    [switch]$Unattended,

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Unattended -and $NonInteractive) {
    [Console]::Error.WriteLine('Unattended 与 NonInteractive 不能同时使用')
    exit 2
}
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $repoRoot 'windows/bootstrap/WindowsBootstrap.psm1') -Force
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    [Console]::Error.WriteLine('Scoop 安装入口只能在 Windows 执行')
    exit 10
}
if (Test-WindowsBootstrapAdministrator) {
    [Console]::Error.WriteLine('Scoop 必须由普通用户安装')
    exit 10
}
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Output '[AlreadyPresent] scoop: Scoop 已安装'
    exit 0
}
if ($WhatIfPreference) {
    Write-Output '[Preview] scoop: 安装当前用户 Scoop'
    exit 0
}
if ($NetworkMode -ne 'Direct' -and [string]::IsNullOrWhiteSpace($InstallerPath)) {
    [Console]::Error.WriteLine("$NetworkMode 缺少显式 Scoop installer；不回退 Direct")
    exit 10
}

$temporaryInstaller = ''
try {
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        $catalog = Import-WindowsBootstrapCatalog -Path (Join-Path $repoRoot 'config/install/windows-packages.psd1')
        $temporaryInstaller = Join-Path $env:TEMP ("install-scoop-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
        Invoke-WebRequest -Uri ([string]$catalog.Scoop.InstallerUrl) -UseBasicParsing -OutFile $temporaryInstaller
        $InstallerPath = $temporaryInstaller
    }
    $resolvedInstaller = [System.IO.Path]::GetFullPath($InstallerPath)
    if (-not (Test-Path -LiteralPath $resolvedInstaller -PathType Leaf)) {
        throw "Scoop installer 不存在: $resolvedInstaller"
    }
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $resolvedInstaller
    if ($LASTEXITCODE -ne 0) {
        throw "Scoop installer 退出码: $LASTEXITCODE"
    }
    $null = Update-WindowsBootstrapPath
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        [Console]::Error.WriteLine('Scoop 安装完成后当前进程仍无法发现 scoop')
        exit 10
    }
    Write-Output '[Succeeded] scoop: 安装完成'
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
finally {
    if ($temporaryInstaller) {
        Remove-Item -LiteralPath $temporaryInstaller -Force -ErrorAction SilentlyContinue
    }
}
