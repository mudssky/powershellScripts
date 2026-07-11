#!/usr/bin/env pwsh

<#
.SYNOPSIS
    将 Linux 发行版 target 与共享运行时 target 组合后调用 package source 引擎。

.PARAMETER DistributionTarget
    ubuntu、debian 或 arch。

.PARAMETER NetworkMode
    Direct、China 或 Auto。

.PARAMETER TransactionId
    根编排器提供的 source 事务 ID。

.PARAMETER OutputFormat
    Text 或 Json。

.OUTPUTS
    Switch-Mirrors.ps1 的文本或单文档 JSON 输出，并保留其退出码。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('ubuntu', 'debian', 'arch')]
    [string]$DistributionTarget,

    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$NetworkMode = 'Direct',

    [string]$TransactionId = '',

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$switchMirrors = Join-Path $repoRoot 'scripts/pwsh/misc/Switch-Mirrors.ps1'
if (-not (Test-Path -LiteralPath $switchMirrors -PathType Leaf)) {
    [Console]::Error.WriteLine("source 引擎不存在: $switchMirrors")
    exit 10
}

$parameters = @{
    Action        = 'Apply'
    Mode          = $NetworkMode
    Phase         = 'Runtime'
    Target        = @($DistributionTarget, 'brew', 'npm', 'pnpm', 'pip', 'go')
    OutputFormat  = $OutputFormat
}
if (-not [string]::IsNullOrWhiteSpace($TransactionId)) {
    $parameters.TransactionId = $TransactionId
}
if ($WhatIfPreference) {
    $parameters.WhatIf = $true
}

& $switchMirrors @parameters
exit $LASTEXITCODE
