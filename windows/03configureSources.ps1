<#
.SYNOPSIS
    Windows Stage 1 source 薄入口。

.PARAMETER NetworkMode
    Direct、China 或 Auto。

.PARAMETER TransactionId
    根编排器 source transaction ID。

.PARAMETER OutputFormat
    Text 或 Json。

.PARAMETER Unattended
    接受根编排器交互参数。

.PARAMETER NonInteractive
    接受根编排器交互参数。

.OUTPUTS
    Invoke-WindowsSources.ps1 返回的单文档结果。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Direct', 'China', 'Auto')]
    [string]$NetworkMode = 'Direct',

    [string]$TransactionId = '',

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Json',

    [switch]$Unattended,

    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Unattended -and $NonInteractive) {
    [Console]::Error.WriteLine('Unattended 与 NonInteractive 不能同时使用')
    exit 2
}
$helperPath = Join-Path $PSScriptRoot 'pwsh/Invoke-WindowsSources.ps1'
& $helperPath `
    -NetworkMode $NetworkMode `
    -TransactionId $TransactionId `
    -OutputFormat $OutputFormat `
    -WhatIf:$WhatIfPreference
exit $LASTEXITCODE
