#!/usr/bin/env pwsh
<#
.SYNOPSIS
    跨平台内存异常分析命令行工具。

.DESCRIPTION
    输出统一 JSON，帮助定位进程占用、系统提交量、Docker 容器内存和 Windows 内核池异常线索。

.PARAMETER CommandName
    顶层命令，支持 `snapshot`、`sample`、`help`。未传时默认 `snapshot`。

.PARAMETER Top
    Top 进程数量。

.PARAMETER Depth
    采集深度，支持 `basic` 和 `full`。

.PARAMETER IntervalSeconds
    sample 命令的采样间隔秒数。

.PARAMETER Count
    sample 命令的采样次数。

.PARAMETER JsonDepth
    JSON 序列化深度。
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$CommandName,

    [ValidateRange(1, 500)]
    [int]$Top = 30,

    [ValidateSet('basic', 'full')]
    [string]$Depth = 'full',

    [ValidateRange(0, 86400)]
    [int]$IntervalSeconds = 300,

    [ValidateRange(1, 10000)]
    [int]$Count = 3,

    [ValidateRange(3, 100)]
    [int]$JsonDepth = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($relativePath in @(
        'core/report.ps1'
        'core/process.ps1'
        'core/docker.ps1'
        'core/thresholds.ps1'
        'platforms/windows.ps1'
        'platforms/linux.ps1'
        'platforms/macos.ps1'
        'core/sampling.ps1'
    )) {
    . (Join-Path $PSScriptRoot $relativePath)
}

<#
.SYNOPSIS
    执行内存诊断顶层命令。

.DESCRIPTION
    负责命令分发，返回帮助文本或可序列化的报告对象。

.PARAMETER CommandName
    顶层命令名。

.PARAMETER Top
    Top 进程数量。

.PARAMETER Depth
    采集深度。

.PARAMETER IntervalSeconds
    sample 命令的采样间隔秒数。

.PARAMETER Count
    sample 命令的采样次数。

.OUTPUTS
    PSCustomObject
    返回包含 `ExitCode`、`Output`、`OutputObject` 的执行结果。
#>
function Invoke-MemoryDiagnosticsCommand {
    [CmdletBinding()]
    param(
        [string]$CommandName,

        [ValidateRange(1, 500)]
        [int]$Top = 30,

        [ValidateSet('basic', 'full')]
        [string]$Depth = 'full',

        [ValidateRange(0, 86400)]
        [int]$IntervalSeconds = 300,

        [ValidateRange(1, 10000)]
        [int]$Count = 3
    )

    $resolvedCommand = if ([string]::IsNullOrWhiteSpace($CommandName)) { 'snapshot' } else { $CommandName.ToLowerInvariant() }

    switch ($resolvedCommand) {
        'help' {
            return [pscustomobject]@{
                ExitCode     = 0
                Output       = Get-MemoryDiagnosticsHelpText
                OutputObject = $null
            }
        }
        'snapshot' {
            return [pscustomobject]@{
                ExitCode     = 0
                Output       = ''
                OutputObject = New-MemoryDiagnosticsReport -Top $Top -Depth $Depth
            }
        }
        'sample' {
            return [pscustomobject]@{
                ExitCode     = 0
                Output       = ''
                OutputObject = Invoke-MemoryDiagnosticsSampling -Count $Count -IntervalSeconds $IntervalSeconds -Top $Top -Depth $Depth
            }
        }
        default {
            return [pscustomobject]@{
                ExitCode     = 2
                Output       = "未知命令: $CommandName`n`n$(Get-MemoryDiagnosticsHelpText)"
                OutputObject = $null
            }
        }
    }
}

if ($env:PWSH_TEST_SKIP_MEMORY_DIAGNOSTICS_MAIN -ne '1') {
    try {
        $result = Invoke-MemoryDiagnosticsCommand `
            -CommandName $CommandName `
            -Top $Top `
            -Depth $Depth `
            -IntervalSeconds $IntervalSeconds `
            -Count $Count

        if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
            Write-Output $result.Output
        }
        elseif ($null -ne $result.OutputObject) {
            $result.OutputObject | ConvertTo-Json -Depth $JsonDepth
        }

        exit $result.ExitCode
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
