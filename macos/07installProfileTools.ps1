#!/usr/bin/env pwsh

<#
.SYNOPSIS
    安装并配置 PowerShell Profile 与仓库工具链。

.PARAMETER Preset
    Core 或 Full；两者共享本步骤。

.PARAMETER Unattended
    无人值守模式，不允许隐藏交互。

.PARAMETER NonInteractive
    严格非交互模式，前置不足时返回 Blocked。

.OUTPUTS
    文本组件结果；任一必需组件失败时退出 1，严格前置缺失时退出 10。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Core', 'Full')]
    [string]$Preset = 'Core',

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
$results = [System.Collections.Generic.List[object]]::new()

function Add-ProfileToolResult {
    <#
    .SYNOPSIS
        向步骤汇总添加组件结果。

    .PARAMETER Name
        组件名称。

    .PARAMETER Status
        Succeeded、AlreadyPresent、Preview、Failed 或 Blocked。

    .PARAMETER Message
        结果摘要。

    .OUTPUTS
        None。结果写入脚本级列表。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'AlreadyPresent', 'Preview', 'Failed', 'Blocked')]
        [string]$Status,

        [string]$Message = ''
    )

    $results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Message = $Message })
}

function Invoke-ProfileToolCommand {
    <#
    .SYNOPSIS
        以参数数组执行一个必需的原生命令。

    .PARAMETER Name
        汇总组件名称。

    .PARAMETER FilePath
        可执行文件路径或命令名。

    .PARAMETER ArgumentList
        原生命令参数数组。

    .OUTPUTS
        None。命令结果写入脚本级列表。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList
    )

    if ($WhatIfPreference) {
        Add-ProfileToolResult -Name $Name -Status Preview -Message ("{0} {1}" -f $FilePath, ($ArgumentList -join ' ')).Trim()
        return
    }

    try {
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "命令退出码为 $LASTEXITCODE"
        }
        Add-ProfileToolResult -Name $Name -Status Succeeded
    }
    catch {
        Add-ProfileToolResult -Name $Name -Status Failed -Message $_.Exception.Message
    }
}

Import-Module (Join-Path $repoRoot 'psutils') -Force

try {
    $moduleResults = @(& (Join-Path $repoRoot 'profile/installer/installModules.ps1') -Platform macOS -WhatIf:$WhatIfPreference)
    $moduleFailures = @($moduleResults | Where-Object Status -eq 'Failed')
    Add-ProfileToolResult `
        -Name modules `
        -Status $(if ($moduleFailures.Count -gt 0) { 'Failed' } elseif ($WhatIfPreference) { 'Preview' } else { 'Succeeded' }) `
        -Message $(if ($moduleFailures.Count -gt 0) { ($moduleFailures.Message -join '; ') } else { '' })
}
catch {
    Add-ProfileToolResult -Name modules -Status Failed -Message $_.Exception.Message
}

try {
    $null = & (Join-Path $repoRoot 'profile/profile.ps1') -LoadProfile -WhatIf:$WhatIfPreference
    Add-ProfileToolResult -Name profile -Status $(if ($WhatIfPreference) { 'Preview' } else { 'Succeeded' })
}
catch {
    Add-ProfileToolResult -Name profile -Status Failed -Message $_.Exception.Message
}

if ($WhatIfPreference) {
    Add-ProfileToolResult -Name node-runtime -Status Preview -Message 'fnm install --lts; fnm use lts-latest'
}
elseif (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
    Add-ProfileToolResult -Name node-runtime -Status Blocked -Message '缺少 fnm，请先完成 05 core-cli'
}
else {
    Invoke-ProfileToolCommand -Name node-install -FilePath fnm -ArgumentList @('install', '--lts')
    if (-not @($results | Where-Object { $_.Name -eq 'node-install' -and $_.Status -eq 'Failed' })) {
        Invoke-ProfileToolCommand -Name node-use -FilePath fnm -ArgumentList @('use', 'lts-latest')
    }
}

$packageConfig = (Resolve-ConfigSources -Sources @(
        @{ Type = 'JsonFile'; Name = 'RootPackage'; Path = (Join-Path $repoRoot 'package.json') }
    ) -BasePath $repoRoot -ErrorOnMissing).Values
$packageManagerSpec = [string]$packageConfig.packageManager
if ([string]::IsNullOrWhiteSpace($packageManagerSpec)) {
    Add-ProfileToolResult -Name pnpm -Status Failed -Message '根 package.json 缺少 packageManager'
}
elseif ($WhatIfPreference) {
    Add-ProfileToolResult -Name pnpm -Status Preview -Message "准备 $packageManagerSpec"
}
elseif (Get-Command corepack -ErrorAction SilentlyContinue) {
    Invoke-ProfileToolCommand -Name corepack-enable -FilePath corepack -ArgumentList @('enable')
    Invoke-ProfileToolCommand -Name pnpm -FilePath corepack -ArgumentList @('prepare', $packageManagerSpec, '--activate')
}
elseif (Get-Command npm -ErrorAction SilentlyContinue) {
    Invoke-ProfileToolCommand -Name pnpm -FilePath npm -ArgumentList @('install', '--global', $packageManagerSpec)
}
else {
    Add-ProfileToolResult -Name pnpm -Status Blocked -Message '缺少 corepack 和 npm'
}

$manageBinArguments = @('-NoLogo', '-NoProfile', '-File', (Join-Path $repoRoot 'Manage-BinScripts.ps1'), '-Action', 'sync', '-Force')
if ($WhatIfPreference) {
    $manageBinArguments += '-WhatIf'
}
Invoke-ProfileToolCommand -Name bin-shims -FilePath pwsh -ArgumentList $manageBinArguments

Invoke-ProfileToolCommand -Name bash-build -FilePath bash -ArgumentList @((Join-Path $repoRoot 'scripts/bash/build.sh'))
Invoke-ProfileToolCommand -Name node-install -FilePath pnpm -ArgumentList @('--dir', (Join-Path $repoRoot 'scripts/node'), 'install', '--ignore-scripts')
Invoke-ProfileToolCommand -Name node-build -FilePath pnpm -ArgumentList @('--dir', (Join-Path $repoRoot 'scripts/node'), 'run', 'build')

if ($WhatIfPreference) {
    Add-ProfileToolResult -Name nbstripout -Status Preview -Message 'uv tool install nbstripout'
}
elseif (Get-Command nbstripout -ErrorAction SilentlyContinue) {
    Add-ProfileToolResult -Name nbstripout -Status AlreadyPresent
}
elseif (Get-Command uv -ErrorAction SilentlyContinue) {
    Invoke-ProfileToolCommand -Name nbstripout -FilePath uv -ArgumentList @('tool', 'install', 'nbstripout')
}
else {
    Add-ProfileToolResult -Name nbstripout -Status Blocked -Message '缺少 uv，请先完成 05 core-cli'
}

foreach ($result in $results) {
    Write-Output ('[{0}] {1}: {2}' -f $result.Status, $result.Name, $result.Message)
}
if (@($results | Where-Object Status -eq 'Failed').Count -gt 0) {
    exit 1
}
if (@($results | Where-Object Status -eq 'Blocked').Count -gt 0) {
    exit 10
}
exit 0
